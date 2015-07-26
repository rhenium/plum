using Plum::BinaryString

module Plum
  class Stream
    attr_reader :id, :state
    attr_reader :weight, :parent, :exclusive

    def initialize(con, id, state: :idle, weight: 16, parent: nil, exclusive: false)
      @connection = con
      @id = id
      @state = state
      @continuation = []
      @callbacks = Hash.new {|hash, key| hash[key] = [] }

      update_dependency(weight: weight, parent: parent, exclusive: exclusive)
    end

    def children
      @connection.streams.select {|c| c.parent == self }
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
      else # :ping, :goaway, :settings, :push_promise
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
    end

    def promise(headers) # TODO: fragment
      stream = @connection.reserve_stream(weight: self.weight + 1, parent: self)
      payload = "".force_encoding(Encoding::BINARY)
      payload.push_uint32((0 << 31 | stream.id))
      payload.push(@connection.hpack_encoder.encode(headers))

      original = Frame.new(type: :push_promise,
                           flags: [:end_headers],
                           stream_id: id,
                           payload: payload)
      original.split(@connection.remote_settings[:max_frame_size]).each do |frame|
        send frame
      end
      stream
    end

    def on(name, &blk)
      @callbacks[name] << blk
    end

    private
    def callback(name, *args)
      @callbacks[name].each {|cb| cb.call(*args) }
    end

    def update_dependency(weight: nil, parent: nil, exclusive: nil)
      @weight = weight unless weight.nil?
      @parent = parent unless parent.nil?
      @exclusive = exclusive unless exclusive.nil?

      if exclusive == true
        @connection.streams[parent].children.each do |child|
          next if child == self
          child.parent = self
        end
      end
    end

    def send_headers(headers, end_stream:)
      max = @connection.remote_settings[:max_frame_size]
      encoded = @connection.hpack_encoder.encode(headers)
      original_frame = Frame.new(type: :headers,
                                 flags: [:end_headers, end_stream ? :end_stream : nil].compact,
                                 stream_id: id,
                                 payload: encoded)
      original_frame.split(max).each do |frame|
        send frame
      end
      @state = :half_closed_local if end_stream
    end

    def send_data(data, end_stream: true)
      max = @connection.remote_settings[:max_frame_size]
      if data.is_a?(IO)
        while !data.eof? && fragment = data.readpartial(max)
          send Frame.new(type: :data,
                         stream_id: id,
                         flags: (end_stream && data.eof? && [:end_stream]),
                         payload: fragment)
        end
      else
        original = Frame.new(type: :data,
                             stream_id: id,
                             flags: (end_stream && [:end_stream]),
                             payload: data.to_s)
        original.split(max).each do |frame|
          send frame
        end
      end
      @state = :half_closed_local if end_stream
    end

    def process_data(frame)
      if @state != :open && @state != :half_closed_local
        raise StreamError.new(:stream_closed)
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
        process_priority_payload(payload.shift(5))
        first_length -= 5
      end

      if padding_length > first_length
        raise Plum::ConnectionError.new(:protocol_error, "padding is too long")
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

      update_dependency(weight: weight, parent: @connection.streams[dependency_id], exclusive: e)
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
  end
end
