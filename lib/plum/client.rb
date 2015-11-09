# -*- frozen-string-literal: true -*-
module Plum
  class Client
    DEFAULT_CONFIG = {
      tls: true,
      scheme: "https",
      verify_mode: OpenSSL::SSL::VERIFY_PEER,
      ssl_context: nil,
      hostname: nil,
      http2_settings: {},
      user_agent: "plum/#{Plum::VERSION}",
      http2: true,
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
          resume
          return ret
        ensure
          close
        end
      end
      self
    end

    # Resume communication with the server, until the specified (or all running) requests are complete.
    # @param response [Response] if specified, waits only for the response
    # @return [Response] if parameter response is specified
    def resume(response = nil)
      if response
        @session.succ until response.failed? || response.finished?
        response
      else
        @session.succ until @session.empty?
      end
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
    # @param options [Hash<Symbol, Object>] request options
    # @param block [Proc] if passed, it will be called when received response headers.
    def request(headers, body, options = {}, &block)
      raise ArgumentError, ":method and :path headers are required" unless headers[":method"] && headers[":path"]
      @session.request(headers, body, options, &block)
    end

    # @!method get!
    # @!method head!
    # @!method delete!
    # @param path [String] the absolute path to request (translated into :path header)
    # @param options [Hash<Symbol, Object>] the request options
    # @param block [Proc] if specified, calls the block when finished
    # Shorthand method for `Client#resume(Client#request(*args))`

    # @!method get
    # @!method head
    # @!method delete
    # @param path [String] the absolute path to request (translated into :path header)
    # @param options [Hash<Symbol, Object>] the request options
    # @param block [Proc] if specified, calls the block when finished
    # Shorthand method for `#request`
    %w(GET HEAD DELETE).each { |method|
      define_method(:"#{method.downcase}!") do |path, options = {}, &block|
        resume _request_helper(method, path, nil, options, &block)
      end
      define_method(:"#{method.downcase}") do |path, options = {}, &block|
        _request_helper(method, path, nil, options, &block)
      end
    }
    # @!method post!
    # @!method put!
    # @param path [String] the absolute path to request (translated into :path header)
    # @param body [String] the request body
    # @param options [Hash<Symbol, Object>] the request options
    # @param block [Proc] if specified, calls the block when finished
    # Shorthand method for `Client#resume(Client#request(*args))`

    # @!method post
    # @!method put
    # @param path [String] the absolute path to request (translated into :path header)
    # @param body [String] the request body
    # @param options [Hash<Symbol, Object>] the request options
    # @param block [Proc] if specified, calls the block when finished
    # Shorthand method for `#request`
    %w(POST PUT).each { |method|
      define_method(:"#{method.downcase}!") do |path, body, options = {}, &block|
        resume _request_helper(method, path, body, options, &block)
      end
      define_method(:"#{method.downcase}") do |path, body, options = {}, &block|
        _request_helper(method, path, body, options, &block)
      end
    }

    private
    def _start
      @started = true

      http2 = @config[:http2]
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
          elsif @socket.respond_to?(:npn_protocol) # TODO: remove
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
      if @config[:http2]
        ctx.ciphers = "ALL:!" + HTTPSServerConnection::CIPHER_BLACKLIST.join(":!")
        if ctx.respond_to?(:alpn_protocols)
          ctx.alpn_protocols = ["h2", "http/1.1"]
        end
        if ctx.respond_to?(:npn_select_cb) # TODO: RFC 7540 does not define protocol negotiation with NPN
          ctx.npn_select_cb = -> protocols {
            protocols.include?("h2") ? "h2" : protocols.first
         }
        end
      end
      ctx
    end

    def _request_helper(method, path, body, options, &block)
      base = { ":method" => method,
               ":path" => path,
               "user-agent" => @config[:user_agent] }
      base.merge!(options[:headers]) if options[:headers]
      request(base, body, options, &block)
    end
  end
end
