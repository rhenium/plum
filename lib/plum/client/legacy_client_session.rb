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
      @parser << @socket.readpartial(1024)
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

    def request(headers, body = nil, &headers_cb)
      response = Response.new
      @requests << [response, headers, body, headers_cb]
      consume_queue
      response
    end

    private
    def fail(exception)
      close
      raise exception
    end

    def consume_queue
      return if @response

      response, headers, body, cb = @requests.shift
      headers["host"] = headers[":authority"] || headers["host"] || @config[:hostname]
      @response = response
      @headers_callback = cb

      @socket << "%s %s HTTP/1.1\r\n" % [headers[":method"], headers[":path"]]
      headers.each { |key, value|
        next if key.start_with?(":") # HTTP/2 psuedo headers
        @socket << "%s: %s\r\n" % [key, value]
      }
      @socket << "\r\n"

      if body
        @socket << body
      end
    end

    def setup_parser
      parser = HTTP::Parser.new
      parser.on_headers_complete = proc {
        resp_headers = parser.headers.map { |key, value| [key.downcase, value] }.to_h
        @response._headers({ ":status" => parser.status_code }.merge(resp_headers))
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
