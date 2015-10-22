module Rack
  module Handler
    class Plum
      def self.run(app, options = {})
        opts = default_options.merge(options)

        config = ::Plum::Rack::Config.new(
          listeners: [
            {
              listener: ::Plum::Rack::TCPListener,
              hostname: opts[:Host],
              port: opts[:Port].to_i
            }
          ],
          debug: !!opts[:Debug]
        )

        @server = ::Plum::Rack::Server.new(app, config)
        yield @server if block_given?
        @server.start
      end

      def self.valid_options
        {
          "Host=HOST"    => "Hostname to listen on (default: #{default_options[:Host]})",
          "Port=PORT"    => "Port to listen on (default: #{default_options[:Port]})",
          "Debug"        => "Turn on debug mode (default: #{default_options[:Debug]})",
        }
      end

      private
      def self.default_options
        rack_env = ENV["RACK_ENV"] || "development"
        default_options = {
          Host: rack_env == "development" ? "localhost" : "0.0.0.0",
          Port: 8080,
          Debug: true,
        }
      end
    end

    register(:plum, ::Rack::Handler::Plum)
  end
end
