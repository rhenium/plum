using Plum::BinaryString

module Plum
  class HTTPConnection < Connection
    def initialize(io, local_settings = {})
      require "http/parser"
      super
      @_headers = nil
      @_body = ""
      @_http_parser = setup_parser
    end

    private
    def negotiate!
      super
    rescue ConnectionError
      # Upgrade from HTTP/1.1
      offset = @_http_parser << @buffer
      @buffer.byteshift(offset)
    end

    def setup_parser
      parser = HTTP::Parser.new
      parser.on_headers_complete = proc {|_headers|
        @_headers = _headers.map {|n, v| [n.downcase, v] }.to_h
      }
      parser.on_body = proc {|chunk| @_body << chunk }
      parser.on_message_complete = proc {|env|
        connection = @_headers["connection"] || ""
        upgrade = @_headers["upgrade"] || ""
        settings = @_headers["http2-settings"]

        if (connection.split(", ").sort == ["Upgrade", "HTTP2-Settings"].sort &&
            upgrade.split(", ").include?("h2c") &&
            settings != nil)
          switch_protocol(settings)
        else
          raise LegacyHTTPError.new(@_headers, @_body, parser)
        end
      }

      parser
    end

    def switch_protocol(settings)
      self.on(:negotiated) {
        _frame = Frame.new(type: :settings, stream_id: 0, payload: Base64.urlsafe_decode64(settings))
        receive_settings(_frame, send_ack: false) # HTTP2-Settings
        process_first_request
      }

      resp = ""
      resp << "HTTP/1.1 101 Switching Protocols\r\n"
      resp << "Connection: Upgrade\r\n"
      resp << "Upgrade: h2c\r\n"
      resp << "Server: plum/#{Plum::VERSION}\r\n"
      resp << "\r\n"

      io.write(resp)
    end

    def process_first_request
      encoder = HPACK::Encoder.new(0, indexing: false) # don't pollute connection's HPACK context
      stream = new_stream(1)
      max_frame_size = local_settings[:max_frame_size]
      headers = @_headers.merge({ ":method" => @_http_parser.http_method,
                                  ":path" => @_http_parser.request_url,
                                  ":authority" => @_headers["host"] })
                         .reject {|n, v| ["connection", "http2-settings", "upgrade", "host"].include?(n) }

      headers_s = Frame.headers(1, encoder.encode(headers), :end_headers).split_headers(max_frame_size) # stream ID is 1
      data_s = Frame.data(1, @_body, :end_stream).split_data(max_frame_size)
      (headers_s + data_s).each {|frag| stream.receive_frame(frag) }
    end
  end
end
