# -*- frozen-string-literal: true -*-
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
    }.freeze

    attr_reader :hpack_encoder, :hpack_decoder
    attr_reader :local_settings, :remote_settings
    attr_reader :state, :streams

    def initialize(writer, local_settings = {})
      @state = :open
      @writer = writer
      @local_settings = Hash.new {|hash, key| DEFAULT_SETTINGS[key] }.merge!(local_settings)
      @remote_settings = Hash.new {|hash, key| DEFAULT_SETTINGS[key] }
      @buffer = String.new
      @streams = {}
      @hpack_decoder = HPACK::Decoder.new(@local_settings[:header_table_size])
      @hpack_encoder = HPACK::Encoder.new(@remote_settings[:header_table_size])
      initialize_flow_control(send: @remote_settings[:initial_window_size],
                              recv: @local_settings[:initial_window_size])
      @max_stream_id = 0
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
    rescue ConnectionError => e
      callback(:connection_error, e)
      goaway(e.http2_error_type)
      close
    end
    alias << receive

    private
    def consume_buffer
      while frame = Frame.parse!(@buffer)
        callback(:frame, frame)
        receive_frame(frame)
      end
    end

    def send_immediately(frame)
      callback(:send_frame, frame)
      @writer.call(frame.assemble)
    end

    def stream(stream_id)
      raise ArgumentError, "stream_id can't be 0" if stream_id == 0

      stream = @streams[stream_id]
      if stream
        if stream.state == :idle && stream.id < @max_stream_id
          stream.set_state(:closed_implicitly)
        end
      elsif stream_id > @max_stream_id
        @max_stream_id = stream_id
        stream = Stream.new(self, stream_id, state: :idle)
        callback(:stream, stream)
        @streams[stream_id] = stream
      else
        stream = Stream.new(self, stream_id, state: :closed_implicitly)
        callback(:stream, stream)
      end

      stream
    end

    def validate_received_frame(frame)
      if @state == :waiting_settings && frame.type != :settings
        raise ConnectionError.new(:protocol_error)
      end

      if @state == :waiting_continuation
        if frame.type != :continuation || frame.stream_id != @continuation_id
          raise ConnectionError.new(:protocol_error)
        end
        if frame.end_headers?
          @state = :open
        end
      end

      if frame.type == :headers || frame.type == :push_promise
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
        stream(frame.stream_id).receive_frame(frame)
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
        receive_goaway(frame)
      when :data, :headers, :priority, :rst_stream, :push_promise, :continuation
        raise Plum::ConnectionError.new(:protocol_error)
      else
        # MUST ignore unknown frame type.
      end
    end

    def receive_settings(frame, send_ack: true)
      if frame.ack?
        raise ConnectionError.new(:frame_size_error) if frame.length != 0
        callback(:settings_ack)
        return
      else
        raise ConnectionError.new(:frame_size_error) if frame.length % 6 != 0
      end

      old_remote_settings = @remote_settings.dup
      @remote_settings.merge!(frame.parse_settings)
      apply_remote_settings(old_remote_settings)

      callback(:remote_settings, @remote_settings, old_remote_settings)

      send_immediately Frame.settings(:ack) if send_ack

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
      raise Plum::ConnectionError.new(:frame_size_error) if frame.length != 8

      if frame.ack?
        callback(:ping_ack)
      else
        opaque_data = frame.payload
        callback(:ping, opaque_data)
        send_immediately Frame.ping(:ack, opaque_data)
      end
    end

    def receive_goaway(frame)
      callback(:goaway, frame)
      goaway
      close

      last_id = frame.payload.uint32(0)
      error_code = frame.payload.uint32(4)
      message = frame.payload.byteslice(8, frame.length - 8)
      if error_code > 0
        raise LocalConnectionError.new(HTTPError::ERROR_CODES.key(error_code), message)
      end
    end
  end
end
