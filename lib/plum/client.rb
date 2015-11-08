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
    # @return [Response] if parameter response is specified
    def wait(response = nil)
      if response
        @session.succ until response.failed? || response.finished?
        response
      else
        @session.succ until @session.empty?
      end
    end

    # Waits for the response headers.
    # @param response [Response] the incomplete response.
    def wait_headers(response)
      @session.succ while !response.failed? && !response.headers
    end

    # Closes the connection immediately.
    def close
      @session.close if @session
    ensure
      @socket.close if @socket
    end

    # Creates a new HTTP request.
    # @param headers [Hash<String, String>] the request headers
    # @param body [String] the request body
    # @param block [Proc] if passed, it will be called when received response headers.
    def request_async(headers, body = nil, &block)
      @session.request(headers, body, &block)
    end

    # Creates a new HTTP request and waits for the response
    # @param headers [Hash<String, String>] the request headers
    # @param body [String] the request body
    def request(headers, body = nil, &block)
      wait @session.request(headers, body, &block)
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
      define_method(:"#{method.downcase}") do |path, headers = {}, &block|
        request({ ":method" => method, ":path" => path }.merge(headers), &block)
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
      define_method(:"#{method.downcase}") do |path, body = nil, headers = {}, &block|
        request({ ":method" => method, ":path" => path }.merge(headers), body, &block)
      end
      define_method(:"#{method.downcase}_async") do |path, body = nil, headers = {}, &block|
        request_async({ ":method" => method, ":path" => path }.merge(headers), body, &block)
      end
    }

    private
    def _start
      @started = true

      http2 = true
      unless @socket
        @socket = TCPSocket.open(host, port)
        if config[:tls]
          ctx = @config[:ssl_context] || new_ssl_ctx
          @socket = OpenSSL::SSL::SSLSocket.new(@socket, ctx)
          @socket.hostname = @config[:hostname] if @socket.respond_to?(:hostname=)
          @socket.sync_close = true
          @socket.connect
          @socket.post_connection_check(@config[:hostname]) if ctx.verify_mode != OpenSSL::SSL::VERIFY_NONE

          if @socket.respond_to?(:alpn_protocol)
            http2 = @socket.alpn_protocol == "h2"
          elsif sock.respond_to?(:npn_protocol)
            http2 = @socket.npn_protocol == "h2"
          else
            http2 = false
          end
        end
      end

      if http2
        @session = ClientSession.new(@socket, @config)
      else
        @session = LegacyClientSession.new(@socket, @config)
      end
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
      if ctx.respond_to?(:npn_select_cb) # TODO: RFC 7540 does not define protocol negotiation with NPN
        ctx.npn_select_cb = -> protocols {
          protocols.include?("h2") ? "h2" : protocols.first
        }
      end
      ctx
    end
  end
end
