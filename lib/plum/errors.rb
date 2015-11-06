# -*- frozen-string-literal: true -*-
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
  end
  class ConnectionError < HTTPError; end
  class StreamError < HTTPError; end

  class LegacyHTTPError < Error
    attr_reader :headers, :data, :parser

    def initialize(headers, data, parser)
      @headers = headers
      @data = data
      @parser = parser
    end
  end

  # Client
  class LocalConnectionError < HTTPError; end
  class LocalStreamError < HTTPError; end
end
