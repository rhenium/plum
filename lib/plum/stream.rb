module Plum
  class Stream
    attr_reader :id, :state, :priority

    def initialize(con, id)
      @connection = con
      @id = id
      @state = :idle
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
      when :settings
        raise Plum::ConnectionError.new(:protocol_error) # stream_id MUST be 0x00
      end

      if frame.flags.include?(:end_stream)
        callback(:complete)
        @state = :half_closed
      end
    rescue Plum::StreamError => e
      callback(:stream_error, e)
      send Frame.new(type: :rst_stream,
                     stream_id: id,
                     payload: [e.http2_error_code].pack("N"))
      close
    end

    def send(frame)
      @connection.send(frame)
    end

    def send_headers(headers, end_stream:)
      max = @connection.remote_settings[:max_frame_size]
      encoded = @connection.hpack_encoder.encode(headers)
      flags = []
      frags << :end_stream if end_stream

      first_fragment = encoded.slice!(0, max)
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
        fragment = data.slice!(0, max)
        send Frame.new(type: :data,
                       stream_id: id,
                       payload: fragment)
      end

      send Frame.new(type: :data,
                     flags: flags,
                     stream_id: id,
                     payload: data)
    end

    def respond(headers, body = nil, end_stream: true) # TODO: priority, padding
      if body
        send_headers(headers, end_stream: false)
        send_data(body, end_stream: end_stream)
      else
        send_headers(headers, end_stream: end_stream)
      end
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

    private
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
        process_priority_payload(payload.slice!(0, 5))
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
      esd = payload.slice(0, 4).unpack("N")[0]
      e = esd >> 31
      dependency_id = e & ~(1 << 31)
      weight = payload.slice(4, 1).unpack("C")[0]
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
      inc = frame.payload.unpack("N")[0]
      if inc == 0
        raise Plum::StreamError.new(:protocol_error)
      end
      # TODO
    end

    def extract_padded(frame)
      if frame.flags.include?(:padded)
        padding_length = frame.payload[0, 1].unpack("C")[0]
        if padding_length > frame.length
          raise Plum::ConnectionError.new(:protocol_error, "padding is too long")
        end
        frame.payload[1, frame.length - padding_length - 1]
      else
        frame.payload
      end
    end
  end
end
