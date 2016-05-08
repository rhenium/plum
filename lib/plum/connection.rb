# frozen-string-literal: true

using Plum::BinaryString

module Plum
  class Connection
    include EventEmitter
    include FlowControl

    CLIENT_CONNECTION_PREFACE = "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

    DEFAULT_SETTINGS = {
      header_table_size:      4096,     # octets
      enable_push:            1,        # 1: enabled, 0: disabled
      max_concurrent_streams: 1 << 30,  # (1 << 31) / 2
      initial_window_size:    65535,    # octets; <= 2 ** 31 - 1
      max_frame_size:         16384,    # octets; <= 2 ** 24 - 1
      max_header_list_size:   (1 << 32) - 1 # Fixnum
    }.freeze

    attr_reader :hpack_encoder, :hpack_decoder
    attr_reader :local_settings, :remote_settings
    attr_reader :state, :streams

    def initialize(writer, local_settings = {})
      @state = :open
      @writer = writer
      @local_settings = Hash.new { |hash, key| DEFAULT_SETTINGS[key] }.merge!(local_settings)
      @remote_settings = Hash.new { |hash, key| DEFAULT_SETTINGS[key] }
      @buffer = String.new
      @streams = {}
      @hpack_decoder = HPACK::Decoder.new(@local_settings[:header_table_size])
      @hpack_encoder = HPACK::Encoder.new(@remote_settings[:header_table_size])
      initialize_flow_control(send: @remote_settings[:initial_window_size],
                              recv: @local_settings[:initial_window_size])
      @max_stream_ids = [0, -1] # [even, odd]
    end

    # Emits :close event. Doesn't actually close socket.
    def close
      return if @state == :closed
      @state = :closed
      # TODO: server MAY wait streams
      callback(:close)
    end

    # Receives the specified data and process.
    # @param new_data [String] The data received from the peer.
    def receive(new_data)
      return if @state == :closed
      return if new_data.empty?
      @buffer << new_data
      consume_buffer
    rescue RemoteConnectionError => e
      callback(:connection_error, e)
      goaway(e.http2_error_type)
      close
    end
    alias << receive

    # Returns a Stream object with the specified ID.
    # @param stream_id [Integer] the stream id
    # @return [Stream] the stream
    def stream(stream_id, update_max_id = true)
      raise ArgumentError, "stream_id can't be 0" if stream_id == 0

      stream = @streams[stream_id]
      if stream
        if stream.state == :idle && stream_id < @max_stream_ids[stream_id % 2]
          stream.set_state(:closed_implicitly)
        end
      elsif stream_id > @max_stream_ids[stream_id % 2]
        @max_stream_ids[stream_id % 2] = stream_id if update_max_id
        stream = Stream.new(self, stream_id, state: :idle)
        callback(:stream, stream)
        @streams[stream_id] = stream
      else
        stream = Stream.new(self, stream_id, state: :closed_implicitly)
        callback(:stream, stream)
      end

      stream
    end

    # Sends local settings to the peer.
    # @param new_settings [Hash<Symbol, Integer>]
    def settings(**new_settings)
      send_immediately Frame::Settings.new(**new_settings)

      old_settings = @local_settings.dup
      @local_settings.merge!(new_settings)

      @hpack_decoder.limit = @local_settings[:header_table_size]
      update_recv_initial_window_size(@local_settings[:initial_window_size] - old_settings[:initial_window_size])
    end

    # Sends a PING frame to the peer.
    # @param data [String] Must be 8 octets.
    # @raise [ArgumentError] If the data is not 8 octets.
    def ping(data = "plum\x00\x00\x00\x00")
      send_immediately Frame::Ping.new(data)
    end

    # Sends GOAWAY frame to the peer and closes the connection.
    # @param error_type [Symbol] The error type to be contained in the GOAWAY frame.
    def goaway(error_type = :no_error, message = "")
      last_id = @max_stream_ids.max
      send_immediately Frame::Goaway.new(last_id, error_type, message)
    end

    # Returns whether peer enables server push or not
    def push_enabled?
      @remote_settings[:enable_push] == 1
    end

    private
    def consume_buffer
      while frame = Frame.parse!(@buffer)
        callback(:frame, frame)
        receive_frame(frame)
      end
    end

    def send_immediately(frame)
      callback(:send_frame, frame)

      if frame.length <= @remote_settings[:max_frame_size]
        @writer.call(frame.assemble)
      else
        frame.split(@remote_settings[:max_frame_size]) { |splitted|
          @writer.call(splitted.assemble)
        }
      end
    end

    def validate_received_frame(frame)
      if @state == :waiting_settings && !(Frame::Settings === frame)
        raise RemoteConnectionError.new(:protocol_error)
      end

      if @state == :waiting_continuation
        if !(Frame::Continuation === frame) || frame.stream_id != @continuation_id
          raise RemoteConnectionError.new(:protocol_error)
        end
        if frame.end_headers?
          @state = :open
        end
      end

      if Frame::Headers === frame || Frame::PushPromise === frame
        if !frame.end_headers?
          @state = :waiting_continuation
          @continuation_id = frame.stream_id
        end
      end
    end

    def receive_frame(frame)
      validate_received_frame(frame)
      consume_recv_window(frame)

      if frame.stream_id == 0
        receive_control_frame(frame)
      else
        stream(frame.stream_id, Frame::Headers === frame).receive_frame(frame)
      end
    end

    def receive_control_frame(frame)
      if frame.length > @local_settings[:max_frame_size]
        raise RemoteConnectionError.new(:frame_size_error)
      end

      case frame
      when Frame::Settings then     receive_settings(frame)
      when Frame::WindowUpdate then receive_window_update(frame)
      when Frame::Ping then         receive_ping(frame)
      when Frame::Goaway then       receive_goaway(frame)
      when Frame::Data, Frame::Headers, Frame::Priority, Frame::RstStream, Frame::PushPromise, Frame::Continuation
        raise Plum::RemoteConnectionError.new(:protocol_error)
      else
        # MUST ignore unknown frame type.
      end
    end

    def receive_settings(frame, send_ack: true)
      if frame.ack?
        raise RemoteConnectionError.new(:frame_size_error) if frame.length != 0
        callback(:settings_ack)
        return
      else
        raise RemoteConnectionError.new(:frame_size_error) if frame.length % 6 != 0
      end

      old_remote_settings = @remote_settings.dup
      @remote_settings.merge!(frame.parse_settings)
      apply_remote_settings(old_remote_settings)

      callback(:remote_settings, @remote_settings, old_remote_settings)

      send_immediately Frame::Settings.ack if send_ack

      if @state == :waiting_settings
        @state = :open
        callback(:negotiated)
      end
    end

    def apply_remote_settings(old_remote_settings)
      @hpack_encoder.limit = @remote_settings[:header_table_size]
      update_send_initial_window_size(@remote_settings[:initial_window_size] - old_remote_settings[:initial_window_size])
    end

    def receive_ping(frame)
      raise Plum::RemoteConnectionError.new(:frame_size_error) if frame.length != 8

      if frame.ack?
        callback(:ping_ack)
      else
        opaque_data = frame.payload
        callback(:ping, opaque_data)
        send_immediately Frame::Ping.new(:ack, opaque_data)
      end
    end

    def receive_goaway(frame)
      callback(:goaway, frame)
      goaway
      close

      # TODO: how handle it?
      # last_id = frame.payload.uint32(0)
      error_code = frame.payload.uint32(4)
      message = frame.payload.byteslice(8, frame.length - 8)
      if error_code > 0
        raise LocalConnectionError.new(HTTPError::ERROR_CODES.key(error_code), message)
      end
    end
  end
end
