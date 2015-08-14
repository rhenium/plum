using Plum::BinaryString

module Plum
  class HTTPConnection < Connection
    def initialize(io, local_settings = {})
      require "http/parser"
      super
      @_http_parser = setup_parser
      @_upgrade_retry = false # After sent 426 (Upgrade Required)
    end

    private
    def setup_parser
      headers = nil
      body = ""
      parser = HTTP::Parser.new
      parser.on_message_begin = proc { }
      parser.on_headers_complete = proc {|_headers| headers = _headers }
      parser.on_body = proc {|chunk| body << chunk }
      parser.on_message_complete = proc do |env|
        # Upgrade from HTTP/1.1
        heads = headers.map {|n, v| [n.downcase, v] }.to_h
        connection = heads["connection"] || ""
        upgrade = heads["upgrade"] || ""
        settings = heads["http2-settings"]

        if (connection.split(", ").sort == ["Upgrade", "HTTP2-Settings"].sort &&
            upgrade.split(", ").include?("h2c") &&
            settings != nil)
          respond_switching_protocol
          self.on(:negotiated) {
            _frame = Frame.new(type: :settings, stream_id: 0, payload: Base64.urlsafe_decode64(settings))
            receive_settings(_frame, send_ack: false) # HTTP2-Settings
            process_first_request(parser, heads, body)
          }
        else
          respond_not_supported
          close
        end
      end

      parser
    end

    def negotiate!
      begin
        super
      rescue ConnectionError
        # Upgrade from HTTP/1.1
        offset = @_http_parser << @buffer
        @buffer.byteshift(offset)
      end
    end

    def respond_switching_protocol
      resp = ""
      resp << "HTTP/1.1 101 Switching Protocols\r\n"
      resp << "Connection: Upgrade\r\n"
      resp << "Upgrade: h2c\r\n"
      resp << "\r\n"

      io.write(resp)
    end

    def respond_not_supported
      data = "Use modern web browser with HTTP/2 support."

      resp = ""
      resp << "HTTP/1.1 505 HTTP Version Not Supported\r\n"
      resp << "Content-Type: text/plain\r\n"
      resp << "Content-Length: #{data.bytesize}\r\n"
      resp << "\r\n"
      resp << data

      io.write(resp)
    end

    def process_first_request(parser, heads, dat)
      stream = new_stream(1)
      heads = heads.merge({ ":method" => parser.http_method,
                            ":path" => parser.request_url,
                            ":authority" => heads["host"] })
                   .reject {|n, v| ["connection", "http2-settings", "upgrade", "host"].include?(n) }
      encoder = HPACK::Encoder.new(0, indexing: false) # don't pollute connection's HPACK context
      headers = Frame.headers(1, encoder.encode(heads), :end_headers) # stream ID is 1
      headers.split_headers(local_settings[:max_frame_size]).each {|hfrag| stream.receive_frame(hfrag) }
      data = Frame.data(1, dat, :end_stream)
      data.split_data(local_settings[:max_frame_size]).each {|dfrag| stream.receive_frame(dfrag) }
    end
  end
end
