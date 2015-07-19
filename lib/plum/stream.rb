module Plum
  class Stream
    attr_reader :id, :state, :priority

    def initialize(con, id, state: :idle)
      @connection = con
      @id = id
      @state = state
      @continuation = false
      @header_fragment = nil
      @callbacks = Hash.new {|hash, key| hash[key] = [] }
    end

    def on_frame(frame)
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
        raise Plum::Error.new("unknown frame type: #{frame.inspect}")
      end

      if frame.flags.include?(:end_stream) # :data, :headers
        callback(:complete)
        @state = :half_closed_remote
      end
    rescue Plum::StreamError => e
      callback(:stream_error, e)
      send Frame.new(type: :rst_stream,
                     stream_id: id,
                     payload: [e.http2_error_code].pack("N"))
      close
    end

    def send(frame)
      case @state
      when :idle
        # BUG?
        unless [:headers, :priority].include?(frame.type)
          raise Error.new("can't send frames other than HEADERS or PRIORITY on an idle stream")
        end
      when :reserved_local
        unless [:headers, :rst_stream].include?(frame.type)
          raise Error.new("can't send frames other than HEADERS or RST_STREAM on a reserved (local) stream")
        end
      when :reserved_remote
        unless [:priority, :window_update, :rst_stream].include?(frame.type)
          raise Error.new("can't send frames other than PRIORITY, WINDOW_UPDATE or RST_STREAM on a reserved (remote) stream")
        end
      when :half_closed_local
        unless [:window_update, :priority, :rst_stream].include?(frame.type)
          raise Error.new("can't send frames other than WINDOW_UPDATE, PRIORITY and RST_STREAM on a half-closed (local) stream")
        end
      when :closed
        unless [:priority].include?(frame.type)
          raise Error.new("can't send frames other than PRIORITY on a closed stream")
        end
      when :half_closed_remote, :open
        # open!
      end
      @connection.send(frame)
    end

    def respond(headers, body = nil, end_stream: true) # TODO: priority, padding
      if body
        send_headers(headers, end_stream: false)
        send_data(body, end_stream: end_stream)
      else
        send_headers(headers, end_stream: end_stream)
      end
      @state = :half_closed_local if end_stream
    end

    def promise(headers) # TODO: fragment
      stream = @connection.promise_stream
      payload = BinaryString.new
      payload.push_uint32((0 << 31 | stream.id))
      payload.push(@connection.hpack_encoder.encode(headers))

      send Frame.new(type: :push_promise,
                     flags: [:end_headers],
                     stream_id: id,
                     payload: payload)
      stream
    end

    def close
      @state = :closed
    end

    def on(name, &blk)
      @callbacks[name] << blk
    end

    private
    def callback(name, *args)
      @callbacks[name].each {|cb| cb.call(*args) }
    end

    def send_headers(headers, end_stream:)
      max = @connection.remote_settings[:max_frame_size]
      encoded = @connection.hpack_encoder.encode(headers)
      flags = []
      frags << :end_stream if end_stream

      first_fragment = encoded.shift(max)
      if encoded.bytesize == 0
        send Frame.new(type: :headers,
                       flags: [:end_headers] + flags,
                       stream_id: id,
                       payload: first_fragment)
      else
        send Frame.new(type: :headers,
                       flags: flags,
                       stream_id: id,
                       payload: first_fragment)
        while flagment = encoded.slice!(0, max)
          send Frame.new(type: :continuation,
                         stream_id: id,
                         payload: fragment)
        end
        send Frame.new(type: :continuation,
                       flags: [:end_headers],
                       stream_id: id,
                       payload: fragment)
      end
    end

    def send_data(data, end_stream: ture)
      max = @connection.remote_settings[:max_frame_size]
      data = data.dup
      flags = []
      flags << :end_stream if end_stream

      while data.bytesize > max
        fragment = data.shift(max)
        send Frame.new(type: :data,
                       stream_id: id,
                       payload: fragment)
      end

      send Frame.new(type: :data,
                     flags: flags,
                     stream_id: id,
                     payload: data)
    end

    def process_data(frame)
      if @state != :open && @state != :half_closed_local
        raise Plum::StreamError.new(:stream_closed)
      end

      body = extract_padded(frame)
      callback(:data, body)
    end

    def process_headers(frame)
      callback(:open)
      @state = :open

      payload = extract_padded(frame)
      if frame.flags.include?(:priority)
        process_priority_payload(payload.shift(5))
      end

      if frame.flags.include?(:end_headers)
        callback(:headers, @connection.hpack_decoder.decode(payload).to_h)
      else
        @continuation = payload
      end
    end

    def process_continuation(frame)
      unless @continuation
        raise Plum::ConnectionError.new(:protocol_error)
      end

      @continuation << frame.payload
      if frame.flags.include?(:end_headers)
        headers = @connection.hpack_decoder.decode(@continuation)
        @continuation = nil
        callback(:headers, headers)
      else
        # continue
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
    end

    def process_rst_stream(frame)
      if @state == :idle
        raise Plum::ConnectionError.new(:protocol_error)
      elsif frame.length != 4
        raise Plum::ConnectionError.new(:frame_size_error)
      else
        close
      end
    end

    def process_window_update(frame)
      if frame.size != 4
        raise Plum::ConnectionError.new(:frame_size_error)
      end
      inc = frame.payload.uint32
      if inc == 0
        raise Plum::StreamError.new(:protocol_error)
      end
      # TODO
    end

    def extract_padded(frame)
      if frame.flags.include?(:padded)
        padding_length = frame.payload.uint8(0)
        if padding_length > frame.length
          raise Plum::ConnectionError.new(:protocol_error, "padding is too long")
        end
        frame.payload[1, frame.length - padding_length - 1]
      else
        frame.payload.dup
      end
    end
  end
end
