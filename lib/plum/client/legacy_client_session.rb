# -*- frozen-string-literal: true -*-
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
      @headers_callback = nil
    end

    def succ
      @parser << @socket.readpartial(16384)
    rescue => e # including HTTP::Parser::Error
      fail(e)
    end

    def empty?
      !@response
    end

    def close
      @closed = true
      @response._fail if @response
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

      response = Response.new
      @requests << [response, headers, body, chunked, headers_cb]
      consume_queue
      response
    end

    private
    def fail(exception)
      close
      raise exception
    end

    def consume_queue
      return if @response || @requests.empty?

      response, headers, body, chunked, cb = @requests.shift
      @response = response
      @headers_callback = cb

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
      out = String.new
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
        resp_headers = parser.headers.map { |key, value| [key.downcase, value] }.to_h
        @response._headers({ ":status" => parser.status_code.to_s }.merge(resp_headers))
        @headers_callback.call(@response) if @headers_callback
      }

      parser.on_body = proc { |chunk|
        @response._chunk(chunk)
      }

      parser.on_message_complete = proc { |env|
        @response._finish
        @response = nil
        @headers_callback = nil
        close unless parser.keep_alive?
        consume_queue
      }

      parser
    end
  end
end
