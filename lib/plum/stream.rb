# -*- frozen-string-literal: true -*-
using Plum::BinaryString

module Plum
  class Stream
    include EventEmitter
    include FlowControl
    include StreamUtils

    attr_reader :id, :state, :connection
    attr_reader :weight, :exclusive
    attr_accessor :parent
    # The child (depending on this stream) streams.
    attr_reader :children

    def initialize(con, id, state: :idle, weight: 16, parent: nil, exclusive: false)
      @connection = con
      @id = id
      @state = state
      @continuation = []
      @children = Set.new

      initialize_flow_control(send: @connection.remote_settings[:initial_window_size],
                              recv: @connection.local_settings[:initial_window_size])
      update_dependency(weight: weight, parent: parent, exclusive: exclusive)
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
      when :push_promise
        receive_push_promise(frame)
      when :ping, :goaway, :settings
        raise ConnectionError.new(:protocol_error) # stream_id MUST be 0x00
      else
        # MUST ignore unknown frame
      end
    rescue StreamError => e
      callback(:stream_error, e)
      close(e.http2_error_type)
    end

    # Closes this stream. Sends RST_STREAM frame to the peer.
    # @param error_type [Symbol] The error type to be contained in the RST_STREAM frame.
    def close(error_type = :no_error)
      @state = :closed
      send_immediately Frame.rst_stream(id, error_type)
    end

    # @api private
    def set_state(state)
      @state = state
    end

    # @api private
    def update_dependency(weight: nil, parent: nil, exclusive: nil)
      raise StreamError.new(:protocol_error, "A stream cannot depend on itself.") if parent == self

      if weight
        @weight = weight
      end

      if parent
        @parent = parent
        @parent.children << self
      end

      if exclusive != nil
        @exclusive = exclusive
        if @parent && exclusive
          @parent.children.to_a.each do |child|
            next if child == self
            @parent.children.delete(child)
            child.parent = self
            @children << child
          end
        end
      end
    end

    private
    def send_immediately(frame)
      @connection.send(frame)
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

      if frame.padded?
        padding_length = frame.payload.uint8
        if padding_length >= frame.length
          raise ConnectionError.new(:protocol_error, "padding is too long")
        end
        callback(:data, frame.payload.byteslice(1, frame.length - padding_length - 1))
      else
        callback(:data, frame.payload)
      end

      receive_end_stream if frame.end_stream?
    end

    def receive_complete_headers(frames)
      first = frames.shift
      payload = first.payload

      if first.padded?
        padding_length = payload.uint8
        payload = payload.byteslice(1, payload.bytesize - padding_length - 1)
      else
        padding_length = 0
        payload = payload.dup
      end

      if first.priority?
        receive_priority_payload(payload.byteshift(5))
      end

      if padding_length > payload.bytesize
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

      receive_end_stream if first.end_stream?
    end

    def receive_headers(frame)
      if @state == :reserved_local
        raise ConnectionError.new(:protocol_error)
      elsif @state == :half_closed_remote
        raise StreamError.new(:stream_closed)
      elsif @state == :closed
        raise ConnectionError.new(:stream_closed)
      elsif @state == :closed_implicitly
        raise ConnectionError.new(:protocol_error)
      elsif @state == :idle && self.id.even?
        raise ConnectionError.new(:protocol_error)
      end

      @state = :open
      callback(:open)

      if frame.end_headers?
        receive_complete_headers([frame])
      else
        @continuation << frame
      end
    end

    def receive_push_promise(frame)
      raise NotImplementedError

      if promised_stream.state == :closed_implicitly
        # 5.1.1 An endpoint that receives an unexpected stream identifier MUST respond with a connection error of type PROTOCOL_ERROR.
        raise ConnectionError.new(:protocol_error)
      elsif promised_id.odd?
        # 5.1.1 Streams initiated by the server MUST use even-numbered stream identifiers.
        raise ConnectionError.new(:protocol_error)
      end
    end

    def receive_continuation(frame)
      # state error mustn't happen: server_connection validates
      @continuation << frame

      if frame.end_headers?
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

      callback(:rst_stream, frame)
      @state = :closed # MUST NOT send RST_STREAM
    end

    # override EventEmitter
    def callback(name, *args)
      super(name, *args)
      @connection.callback(name, self, *args)
    end
  end
end
