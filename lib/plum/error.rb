module Plum
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
    http_1_1_required:   0x0d,
  }

  class HPACKError < StandardError; end
  class HTTPError < StandardError
    def initialize(type, message = nil)
      @http_error_type = type
      super(message)
    end

    def http2_error_code
      ERROR_CODES[@http_error_type]
    end
  end
  class ConnectionError < HTTPError; end
  class StreamError < HTTPError; end
end
