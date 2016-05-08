# frozen-string-literal: true

using Plum::BinaryString

module Plum
  class Stream
    include EventEmitter
    include FlowControl

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
        raise RemoteConnectionError.new(:protocol_error) # stream_id MUST be 0x00
      else
        # MUST ignore unknown frame
      end
    rescue RemoteStreamError => e
      callback(:stream_error, e)
      send_immediately Frame::RstStream.new(id, e.http2_error_type)
      close
    end

    # Closes this stream. Sends RST_STREAM frame to the peer.
    def close
      @state = :closed
      callback(:close)
    end

    # @api private
    def set_state(state)
      @state = state
    end

    # @api private
    def update_dependency(weight: nil, parent: nil, exclusive: nil)
      raise RemoteStreamError.new(:protocol_error, "A stream cannot depend on itself.") if parent == self

      if weight
        @weight = weight
      end

      (@parent = parent)&.children&.add(self)

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

    # Reserves a stream to server push. Sends PUSH_PROMISE and create new stream.
    # @param headers [Enumerable<String, String>] The *request* headers. It must contain all of them: ':authority', ':method', ':scheme' and ':path'.
    # @return [Stream] The stream to send push response.
    def promise(headers)
      stream = @connection.reserve_stream(weight: self.weight + 1, parent: self)
      encoded = @connection.hpack_encoder.encode(headers)
      frame = Frame::PushPromise.new(id, stream.id, encoded, end_headers: true)
      send frame
      stream
    end

    # Sends response headers. If the encoded frame is larger than MAX_FRAME_SIZE, the headers will be splitted into HEADERS frame and CONTINUATION frame(s).
    # @param headers [Enumerable<String, String>] The response headers.
    # @param end_stream [Boolean] Set END_STREAM flag or not.
    def send_headers(headers, end_stream:)
      encoded = @connection.hpack_encoder.encode(headers)
      frame = Frame::Headers.new(id, encoded, end_headers: true, end_stream: end_stream)
      send frame
      @state = :half_closed_local if end_stream
    end

    # Sends DATA frame. If the data is larger than MAX_FRAME_SIZE, DATA frame will be splitted.
    # @param data [String, IO] The data to send.
    # @param end_stream [Boolean] Set END_STREAM flag or not.
    def send_data(data = "", end_stream: true)
      max = @connection.remote_settings[:max_frame_size]
      if data.is_a?(IO)
        until data.eof?
          fragment = data.readpartial(max)
          send Frame::Data.new(id, fragment, end_stream: end_stream && data.eof?)
        end
      else
        send Frame::Data.new(id, data, end_stream: end_stream)
      end
      @state = :half_closed_local if end_stream
    end

    private
    def send_immediately(frame)
      @connection.send(frame)
    end

    def validate_received_frame(frame)
      if frame.length > @connection.local_settings[:max_frame_size]
        if [:headers, :push_promise, :continuation].include?(frame.type)
          raise RemoteConnectionError.new(:frame_size_error)
        else
          raise RemoteStreamError.new(:frame_size_error)
        end
      end
    end

    def receive_end_stream
      callback(:end_stream)
      @state = :half_closed_remote
    end

    def receive_data(frame)
      if @state != :open && @state != :half_closed_local
        raise RemoteStreamError.new(:stream_closed)
      end

      if frame.padded?
        padding_length = frame.payload.uint8
        if padding_length >= frame.length
          raise RemoteConnectionError.new(:protocol_error, "padding is too long")
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
        raise RemoteConnectionError.new(:protocol_error, "padding is too long")
      end

      frames.each do |frame|
        payload << frame.payload
      end

      begin
        decoded_headers = @connection.hpack_decoder.decode(payload)
      rescue
        raise RemoteConnectionError.new(:compression_error, $!)
      end

      callback(:headers, decoded_headers)

      receive_end_stream if first.end_stream?
    end

    def receive_headers(frame)
      if @state == :reserved_local
        raise RemoteConnectionError.new(:protocol_error)
      elsif @state == :half_closed_remote
        raise RemoteStreamError.new(:stream_closed)
      elsif @state == :closed
        raise RemoteConnectionError.new(:stream_closed)
      elsif @state == :closed_implicitly
        raise RemoteConnectionError.new(:protocol_error)
      elsif @state == :idle && self.id.even?
        raise RemoteConnectionError.new(:protocol_error)
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
        raise RemoteConnectionError.new(:protocol_error)
      elsif promised_id.odd?
        # 5.1.1 Streams initiated by the server MUST use even-numbered stream identifiers.
        raise RemoteConnectionError.new(:protocol_error)
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
        raise RemoteStreamError.new(:frame_size_error)
      end
      receive_priority_payload(frame.payload)
    end

    def receive_priority_payload(payload)
      esd = payload.uint32
      e = (esd >> 31) == 1
      dependency_id = esd & ~(1 << 31)
      weight = payload.uint8(4)

      update_dependency(weight: weight, parent: @connection.streams[dependency_id], exclusive: e)
    end

    def receive_rst_stream(frame)
      if frame.length != 4
        raise RemoteConnectionError.new(:frame_size_error)
      elsif @state == :idle
        raise RemoteConnectionError.new(:protocol_error)
      end
      @state = :closed # MUST NOT send RST_STREAM

      error_code = frame.payload.uint32
      callback(:rst_stream, HTTPError::ERROR_CODES.key(error_code))
    end

    # override EventEmitter
    def callback(name, *args)
      super(name, *args)
      @connection.callback(name, self, *args)
    end
  end
end
