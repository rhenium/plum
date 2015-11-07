# -*- frozen-string-literal: true -*-
module Plum
  class Client
    DEFAULT_CONFIG = {
      tls: true,
      scheme: "https",
      verify_mode: OpenSSL::SSL::VERIFY_PEER,
      ssl_context: nil
    }.freeze

    attr_reader :host, :port, :config
    attr_reader :socket

    # Creates a new HTTP client and starts communication.
    # A shorthand for `Plum::Client.new(args).start(&block)`
    def self.start(host, port = nil, config = {}, &block)
      client = self.new(host, port, config)
      client.start(&block)
    end

    # Creates a new HTTP client.
    # @param host [String | IO] the host to connect, or IO object.
    # @param port [Integer] the port number to connect
    # @param config [Hash<Symbol, Object>] the client configuration
    def initialize(host, port = nil, config = {})
      if host.is_a?(IO)
        @socket = host
      else
        @host = host
        @port = port || (config[:tls] ? 443 : 80)
      end
      @config = DEFAULT_CONFIG.merge(hostname: host).merge(config)
      @response_handlers = {}
      @responses = {}
      @started = false
    end

    # Starts communication.
    # If block passed, waits for asynchronous requests and closes the connection after calling the block.
    def start(&block)
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

    # Waits for the asynchronous response(s) to finish.
    # @param response [Response] if specified, waits only for the response
    def wait(response = nil)
      if response
        _succ while !response.failed? && !response.finished?
      else
        _succ while !@responses.empty?
      end
    end

    # Waits for the response headers.
    # @param response [Response] the incomplete response.
    def wait_headers(response)
      _succ while !response.failed? && !response.headers
    end

    # Closes the connection.
    def close
      @plum.close if @plum
    ensure
      @socket.close if @socket
    end

    # Creates a new HTTP request.
    # @param headers [Hash<String, String>] the request headers
    # @param body [String] the request body
    # @param block [Proc] if specified, calls the block when finished
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

    # Creates a new HTTP request and waits for the response
    # @param headers [Hash<String, String>] the request headers
    # @param body [String] the request body
    def request(headers, body = nil)
      raise ArgumentError, ":method and :path headers are required" unless headers[":method"] && headers[":path"]

      base_headers = { ":method" => nil,
                       ":path" => nil,
                       ":authority" => @config[:hostname],
                       ":scheme" => @config[:scheme] }

      response = request_async(base_headers.merge(headers), body)
      wait(response)
      response
    end

    # @!method get
    # @!method head
    # @!method delete
    # @param path [String] the absolute path to request (translated into :path header)
    # @param headers [Hash] the request headers
    # Shorthand method for `#request`

    # @!method get_async
    # @!method head_async
    # @!method delete_async
    # @param path [String] the absolute path to request (translated into :path header)
    # @param headers [Hash] the request headers
    # @param block [Proc] if specified, calls the block when finished
    # Shorthand method for `#request_async`
    %w(GET HEAD DELETE).each { |method|
      define_method(:"#{method.downcase}") do |path, headers = {}|
        request({ ":method" => method, ":path" => path }.merge(headers))
      end
      define_method(:"#{method.downcase}_async") do |path, headers = {}, &block|
        request_async({ ":method" => method, ":path" => path }.merge(headers), nil, &block)
      end
    }
    # @!method post
    # @!method put
    # @param path [String] the absolute path to request (translated into :path header)
    # @param body [String] the request body
    # @param headers [Hash] the request headers
    # Shorthand method for `#request`

    # @!method post_async
    # @!method put_async
    # @param path [String] the absolute path to request (translated into :path header)
    # @param body [String] the request body
    # @param headers [Hash] the request headers
    # @param block [Proc] if specified, calls the block when finished
    # Shorthand method for `#request_async`
    %w(POST PUT).each { |method|
      define_method(:"#{method.downcase}") do |path, body = nil, headers = {}|
        request({ ":method" => method, ":path" => path }.merge(headers), body)
      end
      define_method(:"#{method.downcase}_async") do |path, body = nil, headers = {}, &block|
        request_async({ ":method" => method, ":path" => path }.merge(headers), body, &block)
      end
    }

    private
    def _start
      @started = true
      unless @socket
        sock = TCPSocket.open(host, port)
        if config[:tls]
          ctx = @config[:ssl_context] || new_ssl_ctx
          sock = OpenSSL::SSL::SSLSocket.new(sock, ctx)
          sock.hostname = @config[:hostname] if sock.respond_to?(:hostname=)
          sock.sync_close = true
          sock.connect
          sock.post_connection_check(@config[:hostname])
        end

        @socket = sock
      end

      @plum = setup_plum(@socket)
    end

    def setup_plum(sock)
      local_settings = {
        enable_push: 0,
        initial_window_size: (1 << 30) - 1,
      }
      plum = ClientConnection.new(sock.method(:write), local_settings)
      plum.on(:protocol_error) { |ex|
        _fail(ex)
        raise ex
      }
      plum.on(:close) { _fail(RuntimeError.new(:closed)) }
      plum.on(:stream_error) { |stream, ex|
        if res = @responses.delete(stream)
          res._fail(ex) unless res.finished?
        end
        raise ex
      }
      plum.on(:headers) { |stream, headers|
        response = @responses[stream]
        response._headers(headers)
        if handler = @response_handlers.delete(stream)
          handler.call(response)
        end
      }
      plum.on(:data) { |stream, chunk|
        response = @responses[stream]
        response._chunk(chunk)
      }
      plum.on(:end_stream) { |stream|
        response = @responses.delete(stream)
        response._finish
      }
      plum
    end

    def _succ
      @plum << @socket.readpartial(1024)
    end

    def _fail(ex)
      while sr = @responses.shift
        stream, res = sr
        res._fail(ex) unless res.finished?
      end
    ensure
      close
    end

    def new_ssl_ctx
      ctx = OpenSSL::SSL::SSLContext.new
      ctx.ssl_version = :TLSv1_2
      ctx.verify_mode = @config[:verify_mode]
      cert_store = OpenSSL::X509::Store.new
      cert_store.set_default_paths
      ctx.cert_store = cert_store
      if ctx.respond_to?(:alpn_protocols)
        ctx.alpn_protocols = ["h2", "http/1.1"]
      end
      if ctx.respond_to?(:npn_select_cb)
        ctx.npn_select_cb = -> protocols {
          protocols.include?("h2") ? "h2" : protocols.first
        }
      end
      ctx
    end
  end
end
