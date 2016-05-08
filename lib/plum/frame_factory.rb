# frozen-string-literal: true

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
      payload = String.new.push_uint32(last_id)
                          .push_uint32(HTTPError::ERROR_CODES[error_type])
                          .push(message)
      Frame.new(type: :goaway, stream_id: 0, payload: payload)
    end

    # Creates a SETTINGS frame.
    # @param ack [Symbol] Pass :ack to create an ACK frame.
    # @param args [Hash<Symbol, Integer>] The settings values to send.
    def settings(ack = nil, **args)
      payload = String.new
      args.each { |key, value|
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
    # @param end_stream [Boolean] add END_STREAM flag
    def data(stream_id, payload = "", end_stream: false)
      payload = payload.b if payload&.encoding != Encoding::BINARY
      fval = end_stream ? 1 : 0
      Frame.new(type_value: 0, stream_id: stream_id, flags_value: fval, payload: payload)
    end

    # Creates a HEADERS frame.
    # @param stream_id [Integer] The stream ID.
    # @param encoded [String] Headers.
    # @param end_stream [Boolean] add END_STREAM flag
    # @param end_headers [Boolean] add END_HEADERS flag
    def headers(stream_id, encoded, end_stream: false, end_headers: false)
      fval = end_stream ? 1 : 0
      fval += 4 if end_headers
      Frame.new(type_value: 1, stream_id: stream_id, flags_value: fval, payload: encoded)
    end

    # Creates a PUSH_PROMISE frame.
    # @param stream_id [Integer] The stream ID.
    # @param new_id [Integer] The stream ID to create.
    # @param encoded [String] Request headers.
    # @param end_headers [Boolean] add END_HEADERS flag
    def push_promise(stream_id, new_id, encoded, end_headers: false)
      payload = String.new.push_uint32(new_id)
                          .push(encoded)
      fval = end_headers ? 4 : 0
      Frame.new(type: :push_promise, stream_id: stream_id, flags_value: fval, payload: payload)
    end

    # Creates a CONTINUATION frame.
    # @param stream_id [Integer] The stream ID.
    # @param payload [String] Payload.
    # @param end_headers [Boolean] add END_HEADERS flag
    def continuation(stream_id, payload, end_headers: false)
      Frame.new(type: :continuation, stream_id: stream_id, flags_value: (end_headers ? 4 : 0), payload: payload)
    end
  end
end
