using Plum::BinaryString

module Plum
  module FrameFactory
    def rst_stream(stream_id, error_type)
      payload = "".push_uint32(HTTPError::ERROR_CODES[error_type])
      Frame.new(type: :rst_stream, stream_id: stream_id, payload: payload)
    end

    def goaway(last_id, error_type, message = "")
      payload = "".push_uint32((last_id || 0) | (0 << 31))
                  .push_uint32(HTTPError::ERROR_CODES[error_type])
                  .push(message)
      Frame.new(type: :goaway, stream_id: 0, payload: payload)
    end

    def settings(ack = nil, **args)
      payload = args.inject("") {|payload, (key, value)|
        id = Frame::SETTINGS_TYPE[key] or raise ArgumentError.new("invalid settings type")
        payload.push_uint16(id)
        payload.push_uint32(value)
      }
      Frame.new(type: :settings, stream_id: 0, flags: [ack], payload: payload)
    end

    def ping(arg1 = "plum\x00\x00\x00\x00", arg2 = nil)
      if !arg2
        raise ArgumentError.new("data must be 8 octets") if arg1.bytesize != 8
        Frame.new(type: :ping, stream_id: 0, payload: arg1)
      else
        Frame.new(type: :ping, stream_id: 0, flags: [:ack], payload: arg2)
      end
    end

    def data(stream_id, payload, *flags)
      Frame.new(type: :data, stream_id: stream_id, flags: flags, payload: payload)
    end

    def headers(stream_id, encoded, *flags)
      Frame.new(type: :headers, stream_id: stream_id, flags: flags, payload: encoded)
    end

    def push_promise(stream_id, new_id, encoded, *flags)
      payload = "".push_uint32(0 << 31 | new_id)
                  .push(encoded)
      Frame.new(type: :push_promise, stream_id: stream_id, flags: flags, payload: payload)
    end

    def continuation(stream_id, payload, *flags)
      Frame.new(type: :continuation, stream_id: stream_id, flags: flags, payload: payload)
    end
  end
end
