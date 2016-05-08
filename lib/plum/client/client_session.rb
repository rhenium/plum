# frozen-string-literal: true

module Plum
  # HTTP/2 client session.
  class ClientSession
    HTTP2_DEFAULT_SETTINGS = {
      enable_push: 0, # TODO: api?
      initial_window_size: 2 ** 30, # TODO
    }

    attr_reader :plum

    def initialize(socket, config)
      @socket = socket
      @config = config
      @http2_settings = HTTP2_DEFAULT_SETTINGS.merge(@config[:http2_settings])

      @plum = setup_plum
      @responses = Set.new
    end

    def succ
      @plum << @socket.readpartial(16384)
    rescue => e
      fail(e)
    end

    def empty?
      @responses.empty?
    end

    def close
      @closed = true
      @responses.each(&:_fail)
      @responses.clear
      @plum.close
    end

    def request(headers, body, options, &headers_cb)
      headers = { ":method" => nil,
                  ":path" => nil,
                  ":authority" => @config[:hostname],
                  ":scheme" => @config[:scheme]
      }.merge(headers)

      response = Response.new(**options)
      @responses << response
      stream = @plum.open_stream
      stream.send_headers(headers, end_stream: !body)
      stream.send_data(body, end_stream: true) if body

      stream.on(:headers) { |resp_headers_raw|
        response._headers(resp_headers_raw)
        headers_cb.call(response) if headers_cb
      }
      stream.on(:data) { |chunk|
        response._chunk(chunk)
        check_window(stream)
      }
      stream.on(:end_stream) {
        response._finish
        @responses.delete(response)
      }
      stream.on(:stream_error) { |ex|
        response._fail
        raise ex
      }
      stream.on(:local_stream_error) { |type|
        response.fail
        raise LocalStreamError.new(type)
      }
      response
    end

    private
    def fail(exception)
      close
      raise exception
    end

    def setup_plum
      plum = ClientConnection.new(@socket.method(:write), @http2_settings)
      plum.on(:connection_error) { |ex|
        fail(ex)
      }
      plum.window_update(@http2_settings[:initial_window_size])
      plum
    end

    def check_window(stream)
      ws = @http2_settings[:initial_window_size]
      stream.window_update(ws) if stream.recv_remaining_window < (ws / 2)
      @plum.window_update(ws) if @plum.recv_remaining_window < (ws / 2)
    end
  end
end
