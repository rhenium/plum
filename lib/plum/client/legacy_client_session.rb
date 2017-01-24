module Plum
  # HTTP/1.x client session.
  class LegacyClientSession
    # Creates a new HTTP/1.1 client session
    def initialize(socket, config)
      require "http/parser"
      @socket = socket
      @config = config

      @parser = setup_parser
      @requests = []
      @response = nil
    end

    def succ
      @parser << @socket.readpartial(16384)
    rescue # including HTTP::Parser::Error
      close
      raise
    end

    def empty?
      !@response
    end

    def close
      @closed = true
      @response.send(:fail) if @response
    end

    def request(headers, body, options, &headers_cb)
      headers["host"] = headers[":authority"] || headers["host"] || @config[:hostname]
      if body
        if headers["content-length"] || headers["transfer-encoding"]
          chunked = false
        else
          chunked = true
          headers["transfer-encoding"] = "chunked"
        end
      end

      response = Response.new(self, **options, &headers_cb)
      @requests << [response, headers, body, chunked]
      consume_queue
      response
    end

    private
    def consume_queue
      return if @response || @requests.empty?

      response, headers, body, chunked = @requests.shift
      @response = response

      @socket << construct_request(headers)

      if body
        if chunked
          read_object(body) { |chunk|
            @socket << chunk.bytesize.to_s(16) << "\r\n" << chunk << "\r\n"
          }
        else
          read_object(body) { |chunk| @socket << chunk }
        end
      end
    end

    def construct_request(headers)
      out = "".b
      out << "%s %s HTTP/1.1\r\n" % [headers[":method"], headers[":path"]]
      headers.each { |key, value|
        next if key.start_with?(":") # HTTP/2 psuedo headers
        out << "%s: %s\r\n" % [key, value]
      }
      out << "\r\n"
    end

    def read_object(body)
      if body.is_a?(String)
        yield body
      else # IO
        until body.eof?
          yield body.readpartial(1024)
        end
      end
    end

    def setup_parser
      parser = HTTP::Parser.new
      parser.on_headers_complete = proc {
        # FIXME: duplicate header name?
        resp_headers = parser.headers.map { |key, value| [key.downcase, value] }.to_h
        @response.send(:set_headers, { ":status" => parser.status_code.to_s }.merge(resp_headers))
      }

      parser.on_body = proc { |chunk|
        @response.send(:add_chunk, chunk)
      }

      parser.on_message_complete = proc { |env|
        @response.send(:finish)
        @response = nil
        close unless parser.keep_alive?
        consume_queue
      }

      parser
    end
  end
end
