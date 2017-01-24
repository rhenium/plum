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
    rescue
      close
      raise
    end

    def empty?
      @responses.empty?
    end

    def close
      @closed = true
      @responses.each { |res| res.send(:fail) }
      @responses.clear
      @plum.close
    end

    def request(headers, body, options, &headers_cb)
      headers = { ":method" => nil,
                  ":path" => nil,
                  ":authority" => @config[:hostname],
                  ":scheme" => @config[:https] ? "https" : "http",
      }.merge(headers)

      response = Response.new(self, **options, &headers_cb)
      @responses << response
      stream = @plum.open_stream
      stream.send_headers(headers, end_stream: !body)
      stream.send_data(body, end_stream: true) if body

      stream.on(:headers) { |resp_headers_raw|
        response.send(:set_headers, resp_headers_raw.to_h)
      }
      stream.on(:data) { |chunk|
        response.send(:add_chunk, chunk)
        check_window(stream)
      }
      stream.on(:end_stream) {
        response.send(:finish)
        @responses.delete(response)
      }
      stream.on(:stream_error) { |ex|
        response.send(:fail, ex)
        raise ex
      }
      stream.on(:local_stream_error) { |type|
        ex = LocalStreamError.new(type)
        response.send(:fail, ex)
        raise ex
      }
      response
    end

    private
    def setup_plum
      plum = ClientConnection.new(@socket.method(:write), @http2_settings)
      plum.on(:connection_error) { |ex|
        close
        raise ex
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
