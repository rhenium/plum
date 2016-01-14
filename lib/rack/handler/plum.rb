# -*- frozen-string-literal: true -*-
require "plum/rack"

module Rack
  module Handler
    class Plum
      def self.run(app, options = {})
        opts = default_options.merge(options)

        config = ::Plum::Rack::Config.new(
          listeners: [
            {
              listener: ::Plum::Rack::TLSListener,
              hostname: opts[:Host],
              port: opts[:Port].to_i
            }
          ],
          debug: !!opts[:Debug],
          threadpool_size: opts[:Threads].to_i
        )

        @server = ::Plum::Rack::Server.new(app, config)
        yield @server if block_given? # TODO
        @server.start
      end

      def self.shutdown
        @server.stop if @server
      end

      def self.valid_options
        {
          "Host=HOST"   => "Hostname to listen on (default: #{default_options[:Host]})",
          "Port=PORT"   => "Port to listen on (default: #{default_options[:Port]})",
          "Debug"       => "Turn on debug mode (default: #{default_options[:Debug]})",
          "Threads=N"   => "Use N threads (default: #{default_options[:Threads]})",
        }
      end

      private
      def self.default_options
        rack_env = ENV["RACK_ENV"] || "development"
        dev = rack_env == "development"
        default_options = {
          Host: dev ? "localhost" : "0.0.0.0",
          Port: 8080,
          Debug: dev,
          Threads: 20,
        }
      end
    end

    register(:plum, ::Rack::Handler::Plum)
  end
end
