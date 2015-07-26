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
    attr_reader :state, :socket, :streams

    def initialize(socket, local_settings = {})
      @socket = socket
      @local_settings = Hash.new {|hash, key| DEFAULT_SETTINGS[key] }.merge!(local_settings)
      @remote_settings = Hash.new {|hash, key| DEFAULT_SETTINGS[key] }
      @callbacks = Hash.new {|hash, key| hash[key] = [] }
      @buffer = "".force_encoding(Encoding::BINARY)
      @streams = {}
      @state = :waiting_connetion_preface
      @hpack_decoder = HPACK::Decoder.new(@local_settings[:header_table_size])
      @hpack_encoder = HPACK::Encoder.new(@remote_settings[:header_table_size])
      @recv_remaining_window = @local_settings[:initial_window_size]
      @send_remaining_window = @remote_settings[:initial_window_size]
      @send_buffer = []
    end

    # Registers an event handler to specified event. An event can have multiple handlers.
    # @param name [String] The name of event.
    # @yield Gives event-specific parameters.
    def on(name, &blk)
      @callbacks[name] << blk
    end

    # Sends frame respecting inner-stream flow control.
    #
    # @param frame [Frame] The frame to be sent.
    def send(frame)
      case frame.type
      when :data
        @send_buffer << frame
        callback(:send_deferred, frame) if @send_remaining_window < frame.length
        consume_send_buffer
      else
        send_immediately frame
      end
    end

    # Starts communication with the peer. It blocks until the socket is closed, or reaches EOF.
    def start
      settings(@local_settings)
      while !@socket.closed? && !@socket.eof?
        self << @socket.readpartial(@local_settings[:max_frame_size])
      end
    rescue Plum::ConnectionError => e
      callback(:connection_error, e)
      close(e.http2_error_code)
    end

    # Closes the connection and closes the socket. Sends GOAWAY frame to the peer.
    #
    # @param error_code [Integer] The error code to be contained in the GOAWAY frame.
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

    # Increases receiving window size. Sends WINDOW_UPDATE frame to the peer.
    #
    # @param wsi [Integer] The amount to increase receiving window size. The legal range is 1 to 2^32-1.
    def window_update(wsi)
      @recv_remaining_window += wsi
      payload = "".push_uint32(wsi & ~(1 << 31))
      send Frame.new(tyoe: :window_update, stream_id: id, payload: payload)
    end

    # Sends local settings to the peer.
    #
    # @param kwargs [Hash<Symbol, Integer>]
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

    # Reserves a new stream to server push.
    #
    # @param args [Hash] The argument to pass to Stram.new.
    def reserve_stream(**args)
      next_id = ((@streams.keys.last / 2).to_i + 1) * 2
      stream = new_stream(next_id, **args)
      stream.reserve
      stream
    end

    # Sends a PING frame to the peer.
    #
    # @param data [String] Must be 8 octets.
    # @raise [ArgumentError] If the data is not 8 octets.
    def ping(data = "plum\x00\x00\x00\x00")
      raise ArgumentError.new("data must be 8 octets") unless data.bytesize == 8
      send Frame.new(type: :ping,
                     stream_id: 0,
                     payload: data)
    end

    # Receives the specified data and process.
    #
    # @param new_data [String] The data received from the peer.
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
      if frame.flags.include?(:ack)
        if frame.length != 0
          raise ConnectionError.new(:frame_size_error)
        end
        return
      else
        if frame.length % 6 != 0
          raise ConnectionError.new(:frame_size_error)
        end
      end

      received = (frame.length / (2 + 4)).times.map {|i|
        id = frame.payload.uint16(6 * i)
        val = frame.payload.uint32(6 * i + 2)
        name = Frame::SETTINGS_TYPE.key(id)
        next unless name # 6.5.2 unknown or unsupported identifier MUST be ignored
        [name, val]
      }.compact

      old_remote_settings = @remote_settings.dup
      @remote_settings.merge!(received.to_h)
      @hpack_encoder.limit = @remote_settings[:header_table_size]

      initial_window_diff = (@remote_settings[:initial_window_size] - old_remote_settings[:initial_window_size])
      @streams.values.each do |stream|
        stream.recv_remaining_window += initial_window_diff
        stream.consume_send_buffer
      end
      @recv_remaining_window += initial_window_diff
      consume_send_buffer

      callback(:remote_settings, @remote_settings, old_remote_settings)

      settings_ack = Frame.new(type: :settings, stream_id: 0x00, flags: [:ack])
      send(settings_ack)
    end

    def process_window_update(frame)
      if frame.length != 4
        raise Plum::ConnectionError.new(:frame_size_error)
      end
      r_wsi = frame.payload.uint32
      r = r_wsi >> 31
      wsi = r_wsi & ~(1 << 31)
      if wsi == 0
        raise Plum::ConnectionError.new(:protocol_error)
      end

      @send_remaining_window += wsi
      consume_send_buffer
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

    def new_stream(stream_id, **args)
      if @streams.size > 0 && @streams.keys.last >= stream_id
        raise Plum::ConnectionError.new(:protocol_error)
      end

      stream = Stream.new(self, stream_id, **args)
      callback(:stream, stream)
      @streams[stream_id] = stream
      stream
    end

    def consume_send_buffer
      while frame = @send_buffer.first
        break if frame.length > @send_remaining_window
        @send_buffer.shift
        @send_remaining_window -= frame.length
        send_immediately frame
      end
    end

    def send_immediately(frame)
      callback(:send_frame, frame)
      @socket.write(frame.assemble)
    end
  end
end
