using Plum::BinaryString

module Plum
  class Stream
    attr_reader :id, :state, :priority

    def initialize(con, id, state: :idle)
      @connection = con
      @id = id
      @state = state
      @substate = nil
      @continuation = []
      @callbacks = Hash.new {|hash, key| hash[key] = [] }
    end

    def reserve
      if @state != :idle
        # reusing stream
        raise Plum::ConnectionError.new(:protocol_error)
      else
        @state = :reserved_local
      end
    end

    def process_frame(frame)
      case @state
      when :idle
        if ![:headers, :priority].include?(frame.type)
          raise Plum::ConnectionError.new(:protocol_error)
        end
      when :reserved_local
        if ![:rst_stream, :priority, :window_update].include?(frame.type)
          raise Plum::ConnectionError.new(:protocol_error)
        end
      when :reserved_remote
        # only client
      when :open
        # accept all
      when :half_closed_local
        # accept all
      when :half_closed_remote
        if ![:window_update, :priority, :rst_stream].include?(frame.type)
          raise Plum::StreamError.new(:stream_closed)
        end
      when :closed
        if ![:priority, :window_update, :rst_stream].include?(frame.type)
          raise Plum::ConnectionError.new(:stream_closed)
        end
      end

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
      end
    rescue Plum::StreamError => e
      callback(:stream_error, e)
      close(e.http2_error_code)
    end

    def close(error_code = 0)
      @state = :closed
      data = "".force_encoding(Encoding::BINARY)
      data.push_uint32(error_code)
      send Frame.new(type: :rst_stream,
                     stream_id: id,
                     payload: data)
    end

    def send(frame)
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
      stream = @connection.reserve_stream
      payload = "".force_encoding(Encoding::BINARY)
      payload.push_uint32((0 << 31 | stream.id))
      payload.push(@connection.hpack_encoder.encode(headers))

      send Frame.new(type: :push_promise,
                     flags: [:end_headers],
                     stream_id: id,
                     payload: payload)
      stream
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
      if data.is_a?(IO)
        while !data.eof? && fragment = data.readpartial(max)
          flags = (data.eof? && [:end_stream])
          send Frame.new(type: :data,
                         stream_id: id,
                         flags: flags,
                         payload: fragment)
        end
      else
        data = data.to_s
        pos = 0
        while pos <= data.bytesize # data may be empty string
          fragment = data.byteslice(pos, max)
          pos += max
          flags = (pos > data.bytesize) && [:end_stream]
          send Frame.new(type: :data,
                         stream_id: id,
                         flags: flags,
                         payload: fragment)
        end
      end
    end

    def process_data(frame)
      body = extract_padded(frame)
      callback(:data, body)

      if frame.flags.include?(:end_stream) # :data, :headers
        callback(:end_stream)
        @state = :half_closed_remote
      end
    end

    def process_complete_headers(frames)
      frames = frames.dup
      first = frames.shift
      payload = extract_padded(first)
      if first.flags.include?(:priority)
        process_priority_payload(payload.shift(5))
      end

      frames.each do |frame|
        payload << frame.payload
      end

      callback(:headers, @connection.hpack_decoder.decode(payload).to_h)

      if first.flags.include?(:end_stream)
        callback(:end_stream)
        @state = :half_closed_remote
      end
    end

    def process_headers(frame)
      callback(:open)
      @state = :open

      if frame.flags.include?(:end_headers)
        process_complete_headers([frame])
      else
        @continuation << frame
      end
    end

    def process_continuation(frame)
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
    end

    def process_rst_stream(frame)
      if frame.length != 4
        raise Plum::ConnectionError.new(:frame_size_error)
      else
        @state = :closed # MUST NOT send RST_STREAM
      end
    end

    def process_window_update(frame)
      if frame.size != 4
        raise Plum::ConnectionError.new(:frame_size_error)
      end
      r_wsi = frame.payload.uint32
      r = r_wsi >> 31
      wsi = r_wsi & ~(1 << 31)
      if wsi == 0
        raise Plum::StreamError.new(:protocol_error)
      else
        # TODO
      end
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
