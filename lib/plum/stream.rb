using Plum::BinaryString

module Plum
  class Stream
    include StreamHelper

    attr_reader :id, :state, :connection
    attr_reader :weight, :exclusive
    attr_accessor :parent, :recv_remaining_window, :send_remaining_window

    def initialize(con, id, state: :idle, weight: 16, parent: nil, exclusive: false)
      @connection = con
      @id = id
      @state = state
      @continuation = []
      @callbacks = Hash.new {|hash, key| hash[key] = [] }
      @recv_remaining_window = @connection.local_settings[:initial_window_size]
      @send_remaining_window = @connection.remote_settings[:initial_window_size]
      @send_buffer = []

      update_dependency(weight: weight, parent: parent, exclusive: exclusive)
    end

    # Returns the child (depending on this stream) streams.
    #
    # @return [Array<Stream>] The child streams.
    def children
      @connection.streams.values.select {|c| c.parent == self }.freeze
    end

    # Processes received frames for this stream. Internal use.
    # @private
    def process_frame(frame)
      validate_received_frame(frame)

      case frame.type
      when :data
        process_data(frame)
      when :headers
        process_headers(frame)
      when :priority
        process_priority(frame)
      when :rst_stream
        process_rst_stream(frame)
      when :window_update
        process_window_update(frame)
      when :continuation
        process_continuation(frame)
      when :ping, :goaway, :settings, :push_promise
        raise Plum::ConnectionError.new(:protocol_error) # stream_id MUST be 0x00
      else
        # MUST ignore unknown frame
      end
    rescue Plum::StreamError => e
      callback(:stream_error, e)
      close(e.http2_error_code)
    end

    # Closes this stream. Sends RST_STREAM frame to the peer.
    #
    # @param error_code [Integer] The error code to be contained in the RST_STREAM frame.
    def close(error_code = 0)
      @state = :closed
      data = "".force_encoding(Encoding::BINARY)
      data.push_uint32(error_code)
      send Frame.new(type: :rst_stream,
                     stream_id: id,
                     payload: data)
    end

    # Sends DATA frames remaining unsended due to the flow control. Internal.
    #
    # @private
    def consume_send_buffer
      while frame = @send_buffer.first
        break if frame.length > @send_remaining_window
        @send_buffer.shift
        @send_remaining_window -= frame.length
        send_immediately frame
      end
    end

    # Sends frame respecting inner-stream flow control.
    #
    # @param frame [Frame] The frame to be sent.
    def send(frame)
      case frame.type
      when :data
        @send_buffer << frame
        callback(:send_deferred, frame) if @send_remaining_window < frame.length
        consume_send_buffer
      else
        send_immediately frame
      end
    end

    # Sends the frame immediately ignoring inner-stream flow control.
    #
    # @param frame [Frame] The frame to be sent.
    def send_immediately(frame)
      callback(:send_frame, frame)
      @connection.send(frame)
    end

    # Registers an event handler to specified event. An event can have multiple handlers.
    # @param name [String] The name of event.
    # @yield Gives event-specific parameters.
    def on(name, &blk)
      @callbacks[name] << blk
    end

    private
    def callback(name, *args)
      @callbacks[name].each {|cb| cb.call(*args) }
    end

    def update_dependency(weight: nil, parent: nil, exclusive: nil)
      raise StreamError.new(:protocol_error, "A stream cannot depend on itself.") if parent == self
      @weight = weight unless weight.nil?
      @parent = parent unless parent.nil?
      @exclusive = exclusive unless exclusive.nil?

      if exclusive == true
        parent.children.each do |child|
          next if child == self
          child.parent = self
        end
      end
    end

    def validate_received_frame(frame)
      if frame.length > @connection.local_settings[:max_frame_size]
        if [:headers, :push_promise, :continuation].include?(frame.type)
          raise ConnectionError.new(:frame_size_error)
        else
          raise StreamError.new(:frame_size_error)
        end
      end
    end

    def process_data(frame)
      if @state != :open && @state != :half_closed_local
        raise StreamError.new(:stream_closed)
      end

      @recv_remaining_window -= frame.length
      if @recv_remaining_window < 0
        raise StreamError.new(:flow_control_error) # MAY
      end

      if frame.flags.include?(:padded)
        padding_length = frame.payload.uint8(0)
        if padding_length >= frame.length
          raise Plum::ConnectionError.new(:protocol_error, "padding is too long")
        end
        body = frame.payload.byteslice(1, frame.length - padding_length - 1)
      else
        body = frame.payload
      end
      callback(:data, body)

      if frame.flags.include?(:end_stream) # :data, :headers
        callback(:end_stream)
        @state = :half_closed_remote
      end
    end

    def process_complete_headers(frames)
      frames = frames.dup
      first = frames.shift

      payload = first.payload
      first_length = first.length
      padding_length = 0

      if first.flags.include?(:padded)
        padding_length = payload.uint8
        first_length -= 1 + padding_length
        payload = payload.byteslice(1, first_length)
      else
        payload = payload.dup
      end

      if first.flags.include?(:priority)
        process_priority_payload(payload.byteshift(5))
        first_length -= 5
      end

      if padding_length > first_length
        raise Plum::ConnectionError.new(:protocol_error, "padding is too long")
      end

      frames.each do |frame|
        payload << frame.payload
      end

      begin
        decoded_headers = @connection.hpack_decoder.decode(payload)
      rescue => e
        raise ConnectionError.new(:compression_error, e)
      end

      callback(:headers, decoded_headers)

      if first.flags.include?(:end_stream)
        callback(:end_stream)
        @state = :half_closed_remote
      end
    end

    def process_headers(frame)
      if @state == :reserved_local
        raise ConnectionError.new(:protocol_error)
      elsif @state == :half_closed_remote
        raise StreamError.new(:stream_closed)
      elsif @state == :closed
        raise ConnectionError.new(:stream_closed)
      end

      @state = :open
      callback(:open)

      if frame.flags.include?(:end_headers)
        process_complete_headers([frame])
      else
        @continuation << frame
      end
    end

    def process_continuation(frame)
      # state error mustn't happen: server_connection validates
      @continuation << frame

      if frame.flags.include?(:end_headers)
        process_complete_headers(@continuation)
        @continuation.clear
      end
    end

    def process_priority(frame)
      if frame.length != 5
        raise Plum::StreamError.new(:frame_size_error)
      end
      process_priority_payload(frame.payload)
    end

    def process_priority_payload(payload)
      esd = payload.uint32
      e = esd >> 31
      dependency_id = e & ~(1 << 31)
      weight = payload.uint8(4)

      update_dependency(weight: weight, parent: @connection.streams[dependency_id], exclusive: e == 1)
    end

    def process_rst_stream(frame)
      if frame.length != 4
        raise Plum::ConnectionError.new(:frame_size_error)
      elsif @state == :idle
        raise ConnectionError.new(:protocol_error)
      end

      @state = :closed # MUST NOT send RST_STREAM
    end

    def process_window_update(frame)
      if frame.length != 4
        raise Plum::ConnectionError.new(:frame_size_error)
      end
      r_wsi = frame.payload.uint32
      r = r_wsi >> 31
      wsi = r_wsi & ~(1 << 31)
      if wsi == 0
        raise Plum::StreamError.new(:protocol_error)
      end

      @send_remaining_window += wsi
      consume_send_buffer
    end
  end
end
