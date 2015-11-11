# -*- frozen-string-literal: true -*-
using Plum::BinaryString

module Plum
  class HTTPServerConnection < ServerConnection
    attr_reader :sock

    def initialize(sock, local_settings = {})
      require "http/parser"
      @_headers = nil
      @_body = String.new
      @_http_parser = setup_parser
      @sock = sock
      super(@sock.method(:write), local_settings)
    end

    # Closes the socket.
    def close
      super
      @sock.close
    end

    private
    def negotiate!
      super
    rescue RemoteConnectionError
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

      resp = "HTTP/1.1 101 Switching Protocols\r\n" +
             "Connection: Upgrade\r\n" +
             "Upgrade: h2c\r\n" +
             "Server: plum/#{Plum::VERSION}\r\n" +
             "\r\n"

      @sock.write(resp)
    end

    def process_first_request
      encoder = HPACK::Encoder.new(0, indexing: false) # don't pollute connection's HPACK context
      stream = stream(1)
      max_frame_size = local_settings[:max_frame_size]
      headers = @_headers.merge({ ":method" => @_http_parser.http_method,
                                  ":path" => @_http_parser.request_url,
                                  ":authority" => @_headers["host"] })
                         .reject {|n, v| ["connection", "http2-settings", "upgrade", "host"].include?(n) }

      stream.receive_frame Frame.headers(1, encoder.encode(headers), :end_headers)
      stream.receive_frame Frame.data(1, @_body, :end_stream)
    end
  end
end
