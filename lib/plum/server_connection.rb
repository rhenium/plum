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

    def initialize(socket, local_settings = {})
      @socket = socket
      @local_settings = DEFAULT_SETTINGS.merge(local_settings)
      @callbacks = Hash.new {|hash, key| hash[key] = [] }
      @buffer = BinaryString.new
      @streams = {}
      @state = :waiting_for_connetion_preface
      @last_stream_id = 0
      @hpack_decoder = HPACK::Decoder.new(@local_settings[:header_table_size])
      @hpack_encoder = HPACK::Encoder.new(DEFAULT_SETTINGS[:header_table_size])
    end

    def send(frame)
      callback(:send_frame, frame)
      @socket.write(frame.assemble)
    end

    def start
      update_settings(@local_settings)

      process(@socket.readpartial(1024)) until @socket.eof?
    rescue Plum::ConnectionError => e
      callback(:connection_error, e)
      data = BinaryString.new
      data.push_uint32(@last_stream_id & ~(1 << 31))
      data.push_uint32(e.http2_error_code)
      data.push("") # debug message
      error = Frame.new(type: :goaway,
                        stream_id: 0,
                        payload: data)
      send(error)
      # TODO: server MAY wait streams
      @socket.close
    end

    def update_settings(**kwargs)
      payload = kwargs.inject(BinaryString.new) {|payload, key, value|
        payload.push_uint16(Frame::SETTINGS_TYPE[key])
        payload.push_uint32(value)
      }
      frame = Frame.new(type: :settings,
                        stream_id: 0,
                        payload: payload)
      send(frame)
    end

    def on(name, &blk)
      @callbacks[name] << blk
    end

    def promise_stream
      next_id = ((@streams.keys.last / 2).to_i + 1) * 2
      stream = Stream.new(self, next_id, state: :reserved)
      @streams[next_id] = stream
      stream
    end

    private
    def callback(name, *args)
      @callbacks[name].each {|cb| cb.call(*args) }
    end

    def process(new_data)
      @buffer << new_data
      if @state == :waiting_for_connetion_preface
        return if @buffer.size < 24
        if @buffer.shift(24) != CLIENT_CONNECTION_PREFACE
          raise Plum::ConnectionError.new(:protocol_error) # (MAY) send GOAWAY. sending.
        end
        @state = :waiting_for_settings
      end

      while frame = Frame.parse!(@buffer)
        callback(:frame, frame)

        if @state == :waiting_for_settings && frame.type != :settings
          raise Plum::ConnectionError.new(:protocol_error)
        end

        if frame.stream_id == 0
          process_control_frame(frame)
        else
          stream = @streams[frame.stream_id]
          if stream
            stream.on_frame(frame)
          else
            new_stream(frame)
          end
          @last_stream_id = [frame.stream_id, @last_stream_id].max
        end
      end
    end

    def process_control_frame(frame)
      case frame.type
      when :settings
        on(:settings)
        @state = :initialized if @state == :waiting_for_settings
        process_settings(frame)
      when :window_update
      when :ping
        on(:ping)
        opaque_data = frame.payload
        send Frame.new(type: :ping,
                       stream_id: 0,
                       flags: [:ack],
                       payload: opaque_data)
      else
        # TODO
      end
    end

    def process_settings(frame)
      payload = frame.payload.dup
      received = (frame.length / (2 + 4)).times.map {
        id = payload.uint16!
        val = payload.uint32!
        [Frame::SETTINGS_TYPE.key(id), val]
      }
      @remote_settings = DEFAULT_SETTINGS.merge(received.to_h)
      @hpack_encoder.limit = @remote_settings[:header_table_size]

      settings_ack = Frame.new(type: :settings, stream_id: 0x00, flags: [:ack])
      send(settings_ack)
    end

    def new_stream(frame)
      if (frame.stream_id % 2 == 0) ||
          (@streams.size > 0 && @streams.keys.last >= frame.stream_id)
        raise Plum::ConnectionError.new(:protocol_error)
      end

      unless frame.type == :headers
        raise Plum::ConnectionError.new(:protocol_error)
      end

      @streams.select {|id, s| s.state == :idle }.each {|id, s| s.close }
      stream = Stream.new(self, frame.stream_id)
      @streams[frame.stream_id] = stream
      callback(:stream, stream)
      stream.on_frame(frame)
    end
  end
end
