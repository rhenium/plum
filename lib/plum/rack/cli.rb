# -*- frozen-string-literal: true -*-
require "optparse"
require "rack/builder"

module Plum
  module Rack
    # CLI runner. Parses command line options and start ::Plum::Rack::Server.
    class CLI
      # Creates new CLI runner and parses command line.
      #
      # @param argv [Array<String>] ARGV
      def initialize(argv)
        @argv = argv
        @options = {}

        parse!
      end

      # Starts ::Plum::Rack::Server
      def run
        @server.start
      end

      private
      def parse!
        @parser = setup_parser
        @parser.parse!(@argv)

        config = transform_options
        # TODO: parse rack_opts?
        rack_app, rack_opts = ::Rack::Builder.parse_file(@argv.shift || "config.ru")

        @server = Plum::Rack::Server.new(rack_app, config)
      end

      def transform_options
        if @options[:config]
          dsl = DSL::Config.new.tap { |c| c.instance_eval(File.read(@options[:config])) }
          config = dsl.config
        else
          config = Config.new
        end

        ENV["RACK_ENV"] = @options[:env] if @options[:env]
        config[:debug] = @options[:debug] unless @options[:debug].nil?
        config[:server_push] = @options[:server_push] unless @options[:server_push].nil?
        config[:threaded] = @options[:threaded] unless @options[:threaded].nil?
        config[:threadpool_size] = @options[:threadpool_size] unless @options[:threadpool_size].nil?

        if @options[:fallback_legacy]
          h, p = @options[:fallback_legacy].split(":")
          config[:fallback_legacy_host] = h
          config[:fallback_legacy_port] = p.to_i
        end

        if @options[:socket]
          config[:listeners] << { listener: UNIXListener,
                                  path: @options[:socket] }
        end

        if !@options[:socket] || @options[:host] || @options[:port]
          if @options[:tls] == false
            config[:listeners] << { listener: TCPListener,
                                    hostname: @options[:host] || "0.0.0.0",
                                    port: @options[:port] || 8080 }
          else
            config[:listeners] << { listener: TLSListener,
                                    hostname: @options[:host] || "0.0.0.0",
                                    port: @options[:port] || 8080,
                                    certificate: @options[:cert],
                                    certificate_key: @options[:cert] && @options[:key] }
          end
        end

        config
      end

      def setup_parser
        parser = OptionParser.new do |o|
          o.on "-C", "--config PATH", "Load PATH as a config" do |arg|
            @options[:config] = arg
          end

          o.on "-D", "--debug", "Run puma in debug mode" do
            @options[:debug] = true
          end

          o.on "-e", "--environment ENV", "Rack environment (default: development)" do |arg|
            @options[:env] = arg
          end

          o.on "-a", "--address HOST", "Bind to host HOST (default: 0.0.0.0)" do |arg|
            @options[:host] = arg
          end

          o.on "-p", "--port PORT", "Bind to port PORT (default: 8080)" do |arg|
            @options[:port] = arg.to_i
          end

          o.on "-S", "--socket PATH", "Bind to UNIX domain socket" do |arg|
            @options[:socket] = arg
          end

          o.on "--http", "Use http URI scheme (use raw TCP)" do |arg|
            @options[:tls] = false
          end

          o.on "--https", "Use https URI scheme (use TLS; default)" do |arg|
            @options[:tls] = true
          end

          o.on "--server-push BOOL", "Enable HTTP/2 server push" do |arg|
            @options[:server_push] = arg != "false"
          end

          o.on "--cert PATH", "Use PATH as server certificate" do |arg|
            @options[:cert] = arg
          end

          o.on "--key PATH", "Use PATH as server certificate's private key" do |arg|
            @options[:key] = arg
          end

          o.on "--threaded", "Call the Rack application in threads (experimental)" do
            @options[:threaded] = true
          end

          o.on "--threadpool-size SIZE", "Set the size of thread pool" do |arg|
            @options[:threadpool_size] = arg.to_i
          end

          o.on "--fallback-legacy HOST:PORT", "Fallbacks if the client doesn't support HTTP/2" do |arg|
            @options[:fallback_legacy] = arg
          end

          o.on "-v", "--version", "Show version" do
            puts "plum version #{::Plum::VERSION}"
            exit(0)
          end

          o.on "-h", "--help", "Show this message" do
            puts o
            exit(0)
          end

          o.banner = "plum [options] [rackup config file]"
        end
      end
    end
  end
end
