# -*- frozen-string-literal: true -*-
using Plum::BinaryString

module Plum
  class HTTPServerConnection < ServerConnection
    def initialize(writer, local_settings = {})
      require "http/parser"
      @negobuf = String.new
      @_http_parser = setup_parser
      super(writer, local_settings)
    end

    private
    def negotiate!
      super
    rescue RemoteConnectionError # Upgrade from HTTP/1.1 or legacy
      @negobuf << @buffer
      offset = @_http_parser << @buffer
      @buffer.byteshift(offset)
    end

    def setup_parser
      headers = nil
      body = String.new

      parser = HTTP::Parser.new
      parser.on_headers_complete = proc { |_headers|
        headers = _headers.map {|n, v| [n.downcase, v] }.to_h
      }
      parser.on_body = proc { |chunk| body << chunk }
      parser.on_message_complete = proc { |env|
        connection = headers["connection"] || ""
        upgrade = headers["upgrade"] || ""
        settings = headers["http2-settings"]

        if (connection.split(", ").sort == ["Upgrade", "HTTP2-Settings"].sort &&
            upgrade.split(", ").include?("h2c") &&
            settings != nil)
          switch_protocol(settings, parser, headers, body)
          @negobuf = @_http_parser = nil
        else
          raise LegacyHTTPError.new("request doesn't Upgrade", @negobuf)
        end
      }

      parser
    end

    def switch_protocol(settings, parser, headers, data)
      self.on(:negotiated) {
        _frame = Frame.new(type: :settings, stream_id: 0, payload: Base64.urlsafe_decode64(settings))
        receive_settings(_frame, send_ack: false) # HTTP2-Settings
        process_first_request(parser, headers, data)
      }

      resp = "HTTP/1.1 101 Switching Protocols\r\n" +
             "Connection: Upgrade\r\n" +
             "Upgrade: h2c\r\n" +
             "Server: plum/#{Plum::VERSION}\r\n" +
             "\r\n"

      @writer.call(resp)
    end

    def process_first_request(parser, headers, body)
      encoder = HPACK::Encoder.new(0, indexing: false) # don't pollute connection's HPACK context
      stream = stream(1)
      max_frame_size = local_settings[:max_frame_size]
      nheaders = headers.merge({ ":method" => parser.http_method,
                                 ":path" => parser.request_url,
                                 ":authority" => headers["host"] })
                        .reject {|n, v| ["connection", "http2-settings", "upgrade", "host"].include?(n) }

      stream.receive_frame Frame.headers(1, encoder.encode(nheaders), end_headers: true)
      stream.receive_frame Frame.data(1, body, end_stream: true)
    end
  end
end
