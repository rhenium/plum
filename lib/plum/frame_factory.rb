# -*- frozen-string-literal: true -*-
using Plum::BinaryString

module Plum
  module FrameFactory
    # Creates a RST_STREAM frame.
    # @param stream_id [Integer] The stream ID.
    # @param error_type [Symbol] The error type defined in RFC 7540 Section 7.
    def rst_stream(stream_id, error_type)
      payload = String.new.push_uint32(HTTPError::ERROR_CODES[error_type])
      Frame.new(type: :rst_stream, stream_id: stream_id, payload: payload)
    end

    # Creates a GOAWAY frame.
    # @param last_id [Integer] The biggest processed stream ID.
    # @param error_type [Symbol] The error type defined in RFC 7540 Section 7.
    # @param message [String] Additional debug data.
    # @see RFC 7540 Section 6.8
    def goaway(last_id, error_type, message = "")
      payload = String.new.push_uint32((last_id || 0) | (0 << 31))
                          .push_uint32(HTTPError::ERROR_CODES[error_type])
                          .push(message)
      Frame.new(type: :goaway, stream_id: 0, payload: payload)
    end

    # Creates a SETTINGS frame.
    # @param ack [Symbol] Pass :ack to create an ACK frame.
    # @param args [Hash<Symbol, Integer>] The settings values to send.
    def settings(ack = nil, **args)
      payload = args.inject(String.new) {|payload, (key, value)|
        id = Frame::SETTINGS_TYPE[key] or raise ArgumentError.new("invalid settings type")
        payload.push_uint16(id)
        payload.push_uint32(value)
      }
      Frame.new(type: :settings, stream_id: 0, flags: [ack], payload: payload)
    end

    # Creates a PING frame.
    # @overload ping(ack, payload)
    #   @param ack [Symbol] Pass :ack to create an ACK frame.
    #   @param payload [String] 8 bytes length data to send.
    # @overload ping(payload = "plum\x00\x00\x00\x00")
    #   @param payload [String] 8 bytes length data to send.
    def ping(arg1 = "plum\x00\x00\x00\x00".b, arg2 = nil)
      if !arg2
        raise ArgumentError.new("data must be 8 octets") if arg1.bytesize != 8
        arg1 = arg1.b if arg1.encoding != Encoding::BINARY
        Frame.new(type: :ping, stream_id: 0, payload: arg1)
      else
        Frame.new(type: :ping, stream_id: 0, flags: [:ack], payload: arg2)
      end
    end

    # Creates a DATA frame.
    # @param stream_id [Integer] The stream ID.
    # @param payload [String] Payload.
    # @param flags [Array<Symbol>] Flags.
    def data(stream_id, payload, *flags)
      payload = payload.b if payload && payload.encoding != Encoding::BINARY
      Frame.new(type: :data, stream_id: stream_id, flags: flags, payload: payload)
    end

    # Creates a HEADERS frame.
    # @param stream_id [Integer] The stream ID.
    # @param encoded [String] Headers.
    # @param flags [Array<Symbol>] Flags.
    def headers(stream_id, encoded, *flags)
      Frame.new(type: :headers, stream_id: stream_id, flags: flags, payload: encoded)
    end

    # Creates a PUSH_PROMISE frame.
    # @param stream_id [Integer] The stream ID.
    # @param new_id [Integer] The stream ID to create.
    # @param encoded [String] Request headers.
    # @param flags [Array<Symbol>] Flags.
    def push_promise(stream_id, new_id, encoded, *flags)
      payload = String.new.push_uint32(new_id)
                          .push(encoded)
      Frame.new(type: :push_promise, stream_id: stream_id, flags: flags, payload: payload)
    end

    # Creates a CONTINUATION frame.
    # @param stream_id [Integer] The stream ID.
    # @param payload [String] Payload.
    # @param flags [Array<Symbol>] Flags.
    def continuation(stream_id, payload, *flags)
      Frame.new(type: :continuation, stream_id: stream_id, flags: flags, payload: payload)
    end
  end
end
