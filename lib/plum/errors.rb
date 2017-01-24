module Plum
  class Error < StandardError; end
  class HPACKError < Error; end
  class HTTPError < Error
    ERROR_CODES = {
      no_error:            0x00,
      protocol_error:      0x01,
      internal_error:      0x02,
      flow_control_error:  0x03,
      settings_timeout:    0x04,
      stream_closed:       0x05,
      frame_size_error:    0x06,
      refused_stream:      0x07,
      cancel:              0x08,
      compression_error:   0x09,
      connect_error:       0x0a,
      enhance_your_calm:   0x0b,
      inadequate_security: 0x0c,
      http_1_1_required:   0x0d
    }.freeze

    attr_reader :http2_error_type

    def initialize(type, message = nil)
      @http2_error_type = type
      super(message)
    end

    def http2_error_code
      ERROR_CODES[@http2_error_type]
    end

    def to_s
      "#{@http2_error_type.to_s.upcase}: #{super}"
    end
  end

  class RemoteHTTPError < HTTPError; end
  class RemoteConnectionError < RemoteHTTPError; end
  class RemoteStreamError < RemoteHTTPError; end
  class LocalHTTPError < HTTPError; end
  class LocalConnectionError < LocalHTTPError; end
  class LocalStreamError < LocalHTTPError; end

  class LegacyHTTPError < Error
    attr_reader :buf

    def initialize(message, buf = nil)
      super(message)
      @buf = buf
    end
  end

  class DecoderError < Error; end
end
