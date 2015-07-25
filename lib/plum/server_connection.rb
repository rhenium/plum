using Plum::BinaryString

module Plum
  class ServerConnection
    CLIENT_CONNECTION_PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

    DEFAULT_SETTINGS = {
      header_table_size:      4096,     # octets
      enable_push:            1,        # 1: enabled, 0: disabled
      max_concurrent_streams: 1 << 30,  # (1 << 31) / 2
      initial_window_size:    65535,    # octets; <= 2 ** 31 - 1
      max_frame_size:         16384,    # octets; <= 2 ** 24 - 1
      max_header_list_size:   (1 << 32) - 1 # Fixnum
    }

    attr_reader :hpack_encoder, :hpack_decoder
    attr_reader :local_settings, :remote_settings
    attr_reader :state, :socket

    def initialize(socket, local_settings = {})
      @socket = socket
      @local_settings = Hash.new {|hash, key| DEFAULT_SETTINGS[key] }.merge!(local_settings)
      @remote_settings = Hash.new {|hash, key| DEFAULT_SETTINGS[key] }
      @callbacks = Hash.new {|hash, key| hash[key] = [] }
      @buffer = "".force_encoding(Encoding::BINARY)
      @streams = {}
      @state = :waiting_connetion_preface
      @hpack_decoder = HPACK::Decoder.new(@local_settings[:header_table_size] || DEFAULT_SETTINGS[:header_table_size])
      @hpack_encoder = HPACK::Encoder.new(DEFAULT_SETTINGS[:header_table_size])
    end

    def on(name, &blk)
      @callbacks[name] << blk
    end

    def send(frame)
      callback(:send_frame, frame)
      @socket.write(frame.assemble)
    end

    def start
      settings(@local_settings)
      while !@socket.closed? && !@socket.eof?
        self << @socket.readpartial(1024)
      end
    rescue Plum::ConnectionError => e
      callback(:connection_error, e)
      close(e.http2_error_code)
    end

    def close(error_code = 0)
      last_id = @streams.keys.reverse_each.find {|id| id.odd? }
      data = ""
      data.push_uint32((last_id || 0) & ~(1 << 31))
      data.push_uint32(error_code)
      data.push("") # debug message
      error = Frame.new(type: :goaway,
                        stream_id: 0,
                        payload: data)
      send(error)
      # TODO: server MAY wait streams
      @socket.close
    end

    def settings(**kwargs)
      payload = kwargs.inject("") {|payload, (key, value)|
        id = Frame::SETTINGS_TYPE[key] or raise ArgumentError.new("invalid settings type")
        payload.push_uint16(id)
        payload.push_uint32(value)
      }
      frame = Frame.new(type: :settings,
                        stream_id: 0,
                        payload: payload)
      send(frame)
    end

    def reserve_stream
      next_id = ((@streams.keys.last / 2).to_i + 1) * 2
      stream = new_stream(next_id)
      stream.reserve
      stream
    end

    def ping(data = "plum\x00\x00\x00\x00")
      raise ArgumentError.new("data must be 8 octets") unless data.bytesize == 8
      send Frame.new(type: :ping,
                     stream_id: 0,
                     payload: data)
    end

    def <<(new_data)
      return if new_data.empty?
      @buffer << new_data

      if @state == :waiting_connetion_preface
        if @buffer.bytesize >= 24
          if @buffer.shift(24) == CLIENT_CONNECTION_PREFACE
            @state = :waiting_settings
          else
            raise Plum::ConnectionError.new(:protocol_error) # (MAY) send GOAWAY. sending.
          end
        else
          if CLIENT_CONNECTION_PREFACE.start_with?(@buffer)
            return # not complete
          else
            raise Plum::ConnectionError.new(:protocol_error) # (MAY) send GOAWAY. sending.
          end
        end
      end

      while frame = Frame.parse!(@buffer)
        callback(:frame, frame)
        process_frame(frame)
      end
    end

    private
    def callback(name, *args)
      @callbacks[name].each {|cb| cb.call(*args) }
    end

    def process_frame(frame)
      if @state == :waiting_settings
        if frame.type == :settings
          @state = :open
        else
          raise Plum::ConnectionError.new(:protocol_error)
        end
      end

      if @state == :waiting_continuation && (frame.type != :continuation || frame.stream_id != @continuation_id)
        raise Plum::ConnectionError.new(:protocol_error)
      end

      case frame.type
      when :headers
        if !frame.flags.include?(:end_headers)
          @state = :waiting_continuation
          @continuation_id = frame.stream_id
        end
      when :continuation
        if frame.flags.include?(:end_headers)
          @state = :open
          @continuation_id = nil
        end
      end

      if frame.stream_id == 0
        process_control_frame(frame)
      else
        if @streams.key?(frame.stream_id)
          stream = @streams[frame.stream_id]
        else
          if frame.stream_id.odd? # stream started by client must have odd ID
            stream = new_stream(frame.stream_id)
          else
            raise Plum::ConnectionError.new(:protocol_error)
          end
        end
        stream.process_frame(frame)
      end
    end

    def process_control_frame(frame)
      case frame.type
      when :settings
        process_settings(frame)
      when :window_update
        process_window_update(frame)
      when :ping
        process_ping(frame)
      when :goaway
        close
      else # :data, :headers, :priority, :rst_stream, :push_promise, :continuation
        raise Plum::ConnectionError.new(:protocol_error)
      end
    end

    def process_settings(frame)
      return if frame.flags.include?(:ack)

      received = (frame.length / (2 + 4)).times.map {|i|
        id = frame.payload.uint16(6 * i)
        val = frame.payload.uint32(6 * i + 2)
        name = Frame::SETTINGS_TYPE.key(id)
        next unless name # 6.5.2 unknown or unsupported identifier MUST be ignored
        [name, val]
      }.compact
      @remote_settings.merge!(received.to_h)
      @hpack_encoder.limit = @remote_settings[:header_table_size]

      callback(:remote_settings, @remote_settings)

      settings_ack = Frame.new(type: :settings, stream_id: 0x00, flags: [:ack])
      send(settings_ack)
    end

    def process_window_update(frame)
      @streams.values.each do |s|
        begin
          s.__send__(:process_window_update, frame)
        rescue Plum::StreamError => e
          raise Plum::ConnectionError.new(e.http2_error_type)
        end
      end
    end

    def process_ping(frame)
      if frame.length != 8
        raise Plum::ConnectionError.new(:frame_size_error)
      end

      if frame.flags.include?(:ack)
        on(:ping_ack)
      else
        on(:ping)
        opaque_data = frame.payload
        send Frame.new(type: :ping,
                       stream_id: 0,
                       flags: [:ack],
                       payload: opaque_data)
      end
    end

    def new_stream(stream_id)
      if @streams.size > 0 && @streams.keys.last >= stream_id
        raise Plum::ConnectionError.new(:protocol_error)
      end

      stream = Stream.new(self, stream_id)
      callback(:stream, stream)
      @streams[stream_id] = stream
      stream
    end
  end
end
