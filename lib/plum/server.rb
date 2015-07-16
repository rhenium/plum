module Plum
  class Server
    CLIENT_CONNECTION_PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
    
    attr_reader :hpack_encoder, :hpack_decoder
    attr_accessor :on_stream, :on_frame, :on_send_frame

    def initialize(socket, settings = nil)
      @socket = socket
      @settings = nil
      @buffer = ""
      @streams = {}
      @state = :waiting_for_connetion_preface
      @last_stream_id = 0
      @hpack_decoder = HPACK::Decoder.new(65536)
      @hpack_encoder = HPACK::Encoder.new(65536)
    end

    def send(frame)
      on(:send_frame, frame)
      @socket.write(frame.assemble)
    end

    def start
      settings_payload = @settings
      settings_frame = Frame.new(type: :settings,
                                 stream_id: 0,
                                 payload: settings_payload)
      send(settings_frame)

      until @socket.eof?
        @buffer << @socket.readpartial(1024)
        process
      end
    rescue Plum::ConnectionError => e
      on(:connection_error, e)
      data = [@last_stream_id & ~(1 << 31)].pack("N")
      data << [e.http2_error_code].pack("N")
      data << ""
      error = Frame.new(type: :goaway,
                        stream_id: 0,
                        payload: data)
      send(error)
    end

    def on(name, *args)
      cb = instance_variable_get("@on_#{name}")
      cb.call(*args) if cb
    end

    private
    def process
      if @state == :waiting_for_connetion_preface
        return if @buffer.size < 24
        if @buffer.slice!(0, 24) != CLIENT_CONNECTION_PREFACE
          raise Plum::ConnectionError.new(:protocol_error) # (MAY) send GOAWAY. sending.
        else
          @state = :waiting_for_settings
          # continue
        end
      end

      while frame = Frame.parse!(@buffer)
        on(:frame, frame)

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
            new_client_stream(frame)
          end
          @last_stream_id = frame.stream_id
        end
      end
    end

    def process_control_frame(frame)
      case frame.type
      when :settings
        @state = :initialized if @state == :waiting_for_settings
        process_settings(frame)
      when :window_update
      else
        # TODO
      end
    end

    def process_settings(frame)
      # apply settings (MUST)
      settings_ack = Frame.new(type: :settings, stream_id: 0x00, flags: [:ack])
      send(settings_ack)
    end
    
    def new_client_stream(frame)
      if (frame.stream_id % 2 == 0) ||
          (@streams.size > 0 && @streams.keys.last >= frame.stream_id)
        raise Plum::ConnectionError.new(:protocol_error)
      end

      unless [:headers, :push_stream].include?(frame.type)
        raise Plum::ConnectionError.new(:protocol_error)
      end

      @streams.select {|id, s| s.state == :idle }.each {|id, s| s.close }
      stream = Stream.new(self, frame.stream_id)
      @streams[frame.stream_id] = stream
      on(:stream, stream)
      stream.on_frame(frame)
    end
  end
end
