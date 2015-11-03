# -*- frozen-string-literal: true -*-
module Plum
  class Client
    DEFAULT_CONFIG = {
      https: true
    }.freeze

    attr_reader :host, :port, :config
    attr_reader :socket

    def self.start(host, port, config = {}, &block)
      client = self.new(host, port, config)
      client.start(&block)
    end

    def initialize(host, port, config = {})
      @host = host
      @port = port
      @config = DEFAULT_CONFIG.merge(config)
      @response_handlers = {}
      @responses = {}
    end

    def start
      raise IOError, "Session already started" if @started
      _start
      if block_given?
        begin
          ret = yield(self)
          wait
          return ret
        ensure
          close
        end
      end
      self
    end

    def wait
      while !@responses.empty?
        _succ
      end
    end

    def close
      begin
        @plum.close if @plum
      ensure
        @socket.close if @socket
      end
    end

    def request_async(headers, body = nil, &block)
      stream = @plum.open_stream
      response = Response.new
      @responses[stream] = response

      if body
        stream.send_headers(headers, end_stream: false)
        stream.send_data(body, end_stream: true)
      else
        stream.send_headers(headers, end_stream: true)
      end

      if block_given?
        @response_handlers[stream] = block
      end

      response
    end

    def request(headers, body = nil)
      response = request_async(headers, body)
      _succ while !response.finished?
      response
    end

    %w(GET POST HEAD PUT DELETE).each { |method|
      define_method(method.downcase.to_sym) do |headers = {}|
        request(headers)
      end

      define_method(:"#{method.downcase}_async") do |headers = {}, &block|
        request_async(headers, &block)
      end
    }

    def https?
      !!@config[:https]
    end

    private
    def _start
      @started = true
      sock = TCPSocket.open(host, port)
      if https?
        ctx = @config[:ssl_context] || new_ssl_ctx
        sock = OpenSSL::SSL::SSLSocket.new(sock, ctx)
        sock.sync_close = true
        sock.connect
        if ctx.verify_mode != OpenSSL::SSL::VERIFY_NONE
          sock.post_connection_check(@config[:hostname] || @host)
        end
      end

      @socket = sock
      @plum = setup_plum(sock)
    end

    def setup_plum(sock)
      local_settings = {
        enable_push: 0,
        initial_window_size: (1 << 30) - 1,
      }
      plum = ClientConnection.new(sock.method(:write), local_settings)
      plum.on(:protocol_error) { |ex| raise ex }
      plum.on(:stream_error) { |stream, ex| raise ex }
      plum.on(:headers) { |stream, headers|
        response = @responses[stream]
        response._headers(headers)
      }
      plum.on(:data) { |stream, chunk|
        response = @responses[stream]
        response._chunk(chunk)
      }
      plum.on(:end_stream) { |stream|
        response = @responses.delete(stream)
        response._finish
        if handler = @response_handlers.delete(stream)
          handler.call(response)
        end
      }
      plum
    end

    def _succ
      @plum << @socket.readpartial(1024)
    end

    def new_ssl_ctx
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ssl_version = :TLSv1_2

      if ctx.respond_to?(:hostname=)
        ctx.hostname = @config[:hostname] || @host
      end

      if ctx.respond_to?(:alpn_protocols)
        ctx.alpn_protocols = ["h2", "http/1.1"]
      end

      if ctx.respond_to?(:npn_select_cb)
        ctx.alpn_select_cb = -> protocols {
          protocols.include?("h2") ? "h2" : protocols.first
        }
      end

      ctx
    end
  end
end
