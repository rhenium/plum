module Plum
  class Stream
    attr_reader :id, :state, :priority
    attr_accessor :on_headers, :on_data, :on_close, :on_open, :on_complete, :on_stream_error

    def initialize(con, id)
      @connection = con
      @id = id
      @state = :idle
      @continuation = false
      @header_fragment = nil
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
      when :push_promise
        process_push_promise(frame)
      when :window_update
        process_window_update(frame)
      when :continuation
        process_continuation(frame)
      when :settings
        raise Plum::ConnectionError.new(:protocol_error) # stream_id MUST be 0x00
      end

      if frame.flags.include?(:end_stream)
        on(:complete)
        @state = :half_closed
      end
    rescue Plum::StreamError => e
      on(:stream_error, e)
      send Frame.new(type: :rst_stream,
                     stream_id: id,
                     payload: [e.http2_error_code].pack("N"))
      close
    end

    def send(frame)
      @connection.send(frame)
    end

    def send_headers(headers, flags = [])
      encoded = @connection.hpack_encoder.encode(headers)
      send Frame.new(type: :headers,
                     flags: [:end_headers] + flags,
                     stream_id: id,
                     payload: encoded)
    end

    def send_body(body, flags = [])
      send Frame.new(type: :data,
                     flags: flags,
                     stream_id: id,
                     payload: body)
    end

    def close
      @state = :closed
    end

    def on(name, *args)
      cb = instance_variable_get("@on_#{name}")
      cb.call(*args) if cb
    end

    private
    def process_data(frame)
      if @state != :open && @state != :half_closed_local
        raise Plum::StreamError.new(:stream_closed)
      end

      body = extract_padded(frame)
      on(:data, body)
    end

    def process_headers(frame)
      on(:open)
      @state = :open

      payload = extract_padded(frame)
      if frame.flags.include?(:priority)
        process_priority_payload(payload.slice!(0, 5))
      end

      if frame.flags.include?(:end_headers)
        on(:headers, @connection.hpack_decoder.decode(payload).to_h)
      else
        @header_fragment = payload
        @continuation = true
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

    def process_push_promise(frame)
      payload = extract_padded(frame)
      rpsid = payload.slice!(0, 4).unpack("N")[0]
      r = rpsid >> 31
      psid = rpsid & ~(1 << 31)
      # TODO
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

    def process_continuation(frame)
      # TODO
      unless @continuation
        raise Plum::ConnectionError.new(:protocol_error)
      end

      @header_fragment << frame.payload
      if frame.flags.include?(:end_headers)
        if @continuation == :push_promise
          @connection.push_promise
        else # @continuation == :headers
          headers = @connection.hpack_decoder.decode(@header_fragment)
        end
        @header_fragment = nil
        @continuation = nil
      else
        # continue
      end
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
