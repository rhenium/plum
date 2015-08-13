using Plum::BinaryString

module Plum
  class Stream
    include EventEmitter
    include FlowControl
    include StreamUtils

    attr_reader :id, :state, :connection
    attr_reader :weight, :exclusive
    attr_accessor :parent

    def initialize(con, id, state: :idle, weight: 16, parent: nil, exclusive: false)
      @connection = con
      @id = id
      @state = state
      @continuation = []

      initialize_flow_control(send: @connection.remote_settings[:initial_window_size],
                              recv: @connection.local_settings[:initial_window_size])
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
    def receive_frame(frame)
      validate_received_frame(frame)
      consume_recv_window(frame)

      case frame.type
      when :data
        receive_data(frame)
      when :headers
        receive_headers(frame)
      when :priority
        receive_priority(frame)
      when :rst_stream
        receive_rst_stream(frame)
      when :window_update
        receive_window_update(frame)
      when :continuation
        receive_continuation(frame)
      when :ping, :goaway, :settings, :push_promise
        raise ConnectionError.new(:protocol_error) # stream_id MUST be 0x00
      else
        # MUST ignore unknown frame
      end
    rescue StreamError => e
      callback(:stream_error, e)
      close(e.http2_error_type)
    end

    # Closes this stream. Sends RST_STREAM frame to the peer.
    #
    # @param error_type [Symbol] The error type to be contained in the RST_STREAM frame.
    def close(error_type = :no_error)
      @state = :closed
      send_immediately Frame.rst_stream(id, error_type)
    end

    private
    def send_immediately(frame)
      callback(:send_frame, frame)
      @connection.send(frame)
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

    def receive_end_stream
      callback(:end_stream)
      @state = :half_closed_remote
    end

    def receive_data(frame)
      if @state != :open && @state != :half_closed_local
        raise StreamError.new(:stream_closed)
      end

      if frame.flags.include?(:padded)
        padding_length = frame.payload.uint8(0)
        if padding_length >= frame.length
          raise ConnectionError.new(:protocol_error, "padding is too long")
        end
        body = frame.payload.byteslice(1, frame.length - padding_length - 1)
      else
        body = frame.payload
      end
      callback(:data, body)

      receive_end_stream if frame.flags.include?(:end_stream)
    end

    def receive_complete_headers(frames)
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
        receive_priority_payload(payload.byteshift(5))
        first_length -= 5
      end

      if padding_length > first_length
        raise ConnectionError.new(:protocol_error, "padding is too long")
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

      receive_end_stream if first.flags.include?(:end_stream)
    end

    def receive_headers(frame)
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
        receive_complete_headers([frame])
      else
        @continuation << frame
      end
    end

    def receive_continuation(frame)
      # state error mustn't happen: server_connection validates
      @continuation << frame

      if frame.flags.include?(:end_headers)
        receive_complete_headers(@continuation)
        @continuation.clear
      end
    end

    def receive_priority(frame)
      if frame.length != 5
        raise StreamError.new(:frame_size_error)
      end
      receive_priority_payload(frame.payload)
    end

    def receive_priority_payload(payload)
      esd = payload.uint32
      e = esd >> 31
      dependency_id = e & ~(1 << 31)
      weight = payload.uint8(4)

      update_dependency(weight: weight, parent: @connection.streams[dependency_id], exclusive: e == 1)
    end

    def receive_rst_stream(frame)
      if frame.length != 4
        raise ConnectionError.new(:frame_size_error)
      elsif @state == :idle
        raise ConnectionError.new(:protocol_error)
      end

      @state = :closed # MUST NOT send RST_STREAM
    end
  end
end
