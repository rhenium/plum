# -*- frozen-string-literal: true -*-
module Plum
  class ClientSession
    HTTP2_DEFAULT_SETTINGS = {
      enable_push: 0, # TODO: api?
      initial_window_size: (1 << 30) - 1, # TODO: maximum size: disable flow control
    }

    def initialize(socket, config)
      @socket = socket
      @config = config

      @plum = setup_plum
      @responses = Set.new
    end

    def succ
      @plum << @socket.readpartial(1024)
    rescue => e
      fail(e)
    end

    def empty?
      @responses.empty?
    end

    def close
      @closed = true
      @responses.each { |response| response._fail }
      @responses.clear
      @plum.close
    end

    def request(headers, body = nil, &headers_cb)
      raise ArgumentError, ":method and :path headers are required" unless headers[":method"] && headers[":path"]

      @responses << (response = Response.new)

      headers = { ":method" => nil,
                  ":path" => nil,
                  ":authority" => @config[:hostname],
                  ":scheme" => @config[:scheme]
                }.merge(headers)

      stream = @plum.open_stream
      stream.send_headers(headers, end_stream: !body)
      stream.send_data(body, end_stream: true) if body

      stream.on(:headers) { |resp_headers_raw|
        response._headers(resp_headers_raw)
        headers_cb.call(response) if headers_cb
      }
      stream.on(:data) { |chunk|
        response._chunk(chunk)
      }
      stream.on(:end_stream) {
        response._finish
        @responses.delete(response)
      }
      stream.on(:stream_error) { |ex|
        response._fail
        raise ex
      }

      response
    end

    private
    def fail(exception)
      close
      raise exception
    end

    def setup_plum
      plum = ClientConnection.new(@socket.method(:write), HTTP2_DEFAULT_SETTINGS)
      plum.on(:connection_error) { |ex|
        fail(ex)
      }
      plum
    end
  end
end
