using Plum::BinaryString

module Plum
  class Connection
    include EventEmitter
    include FlowControl
    include ConnectionUtils

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
    attr_reader :state, :streams, :io

    def initialize(io, local_settings = {})
      @io = io
      @local_settings = Hash.new {|hash, key| DEFAULT_SETTINGS[key] }.merge!(local_settings)
      @remote_settings = Hash.new {|hash, key| DEFAULT_SETTINGS[key] }
      @buffer = "".force_encoding(Encoding::BINARY)
      @streams = {}
      @state = :negotiation
      @hpack_decoder = HPACK::Decoder.new(@local_settings[:header_table_size])
      @hpack_encoder = HPACK::Encoder.new(@remote_settings[:header_table_size])
      initialize_flow_control(send: @remote_settings[:initial_window_size],
                              recv: @local_settings[:initial_window_size])
    end
    private :initialize

    # Starts communication with the peer. It blocks until the io is closed, or reaches EOF.
    def run
      while !@io.closed? && !@io.eof?
        receive @io.readpartial(1024)
      end
    end

    # Closes the io.
    def close
      # TODO: server MAY wait streams
      @io.close
    end

    # Receives the specified data and process.
    #
    # @param new_data [String] The data received from the peer.
    def receive(new_data)
      return if new_data.empty?
      @buffer << new_data

      if @state == :negotiation
        negotiate!
      end

      if @state != :negotiation
        while frame = Frame.parse!(@buffer)
          callback(:frame, frame)
          receive_frame(frame)
        end
      end
    rescue ConnectionError => e
      callback(:connection_error, e)
      goaway(e.http2_error_type)
      close
    end
    alias << receive

    # Reserves a new stream to server push.
    #
    # @param args [Hash] The argument to pass to Stram.new.
    def reserve_stream(**args)
      next_id = ((@streams.keys.last / 2).to_i + 1) * 2
      stream = new_stream(next_id, state: :reserved_local, **args)
      stream
    end

    private
    def send_immediately(frame)
      callback(:send_frame, frame)
      @io.write(frame.assemble)
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

    def validate_received_frame(frame)
      case @state
      when :waiting_settings
        raise ConnectionError.new(:protocol_error) if frame.type != :settings
        @state = :negotiated
        callback(:negotiated)
      when :waiting_continuation
        if frame.type != :continuation || frame.stream_id != @continuation_id
          raise Plum::ConnectionError.new(:protocol_error)
        end

        if frame.flags.include?(:end_headers)
          @state = :open
          @continuation_id = nil
        end
      else
        if [:headers].include?(frame.type)
          if !frame.flags.include?(:end_headers)
            @state = :waiting_continuation
            @continuation_id = frame.stream_id
          end
        end
      end
    end

    def receive_frame(frame)
      validate_received_frame(frame)
      consume_recv_window(frame)

      if frame.stream_id == 0
        receive_control_frame(frame)
      else
        if @streams.key?(frame.stream_id)
          stream = @streams[frame.stream_id]
        else
          if frame.stream_id.even? # stream started by client must have odd ID
            raise Plum::ConnectionError.new(:protocol_error)
          end
          stream = new_stream(frame.stream_id)
        end
        stream.receive_frame(frame)
      end
    end

    def receive_control_frame(frame)
      if frame.length > @local_settings[:max_frame_size]
        raise ConnectionError.new(:frame_size_error)
      end

      case frame.type
      when :settings
        receive_settings(frame)
      when :window_update
        receive_window_update(frame)
      when :ping
        receive_ping(frame)
      when :goaway
        goaway
        close
      when :data, :headers, :priority, :rst_stream, :push_promise, :continuation
        raise Plum::ConnectionError.new(:protocol_error)
      else
        # MUST ignore unknown frame type.
      end
    end

    def receive_settings(frame)
      if frame.flags.include?(:ack)
        raise ConnectionError.new(:frame_size_error) if frame.length != 0
        return
      end

      raise ConnectionError.new(:frame_size_error) if frame.length % 6 != 0

      old_remote_settings = @remote_settings.dup
      @remote_settings.merge!(frame.parse_settings)
      apply_remote_settings(old_remote_settings)

      callback(:remote_settings, @remote_settings, old_remote_settings)

      send_immediately Frame.settings(:ack)
    end

    def apply_remote_settings(old_remote_settings)
      @hpack_encoder.limit = @remote_settings[:header_table_size]
      update_send_initial_window_size(@remote_settings[:initial_window_size] - old_remote_settings[:initial_window_size])
    end

    def receive_ping(frame)
      raise Plum::ConnectionError.new(:frame_size_error) if frame.length != 8

      if frame.flags.include?(:ack)
        on(:ping_ack)
      else
        on(:ping)
        opaque_data = frame.payload
        send_immediately Frame.ping(:ack, opaque_data)
      end
    end
  end
end
