require "rack/handler"
require "plum/rack_server"

module Rack
  module Handler
    class Plum
      def self.run(app, options = {})
        opts = default_options.merge(options)

        puts "Starting Plum::RackServer"
        puts "* Plum HTTP/2 server (#{::Plum::VERSION})"
        puts "* Debug mode: on" if opts[:Debug]
        puts "* Listening on #{opts[:Host]}:#{opts[:Port]}"

        @server = ::Plum::RackServer.new(app, opts)
        yield @server if block_given?
        @server.start
      end

      def self.valid_options
        {
          "Host=HOST"    => "Hostname to listen on (default: #{default_options[:Host]})",
          "Port=PORT"    => "Port to listen on (default: #{default_options[:Port]})",
          "Debug"        => "Turn on debug mode (default: #{default_options[:Verbose]})",
        }
      end

      private
      def self.default_options
        rack_env = ENV["RACK_ENV"] || "development"
        default_options = {
          Host: rack_env == "development" ? "localhost" : "0.0.0.0",
          Port: 8080,
          Debug: false,
        }
      end
    end

    register(:plum, ::Rack::Handler::Plum)
  end
end
