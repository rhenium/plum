# -*- frozen-string-literal: true -*-
module Plum
  module Rack
    module DSL
      class Config
        attr_reader :config

        def initialize
          @config = ::Plum::Rack::Config::DEFAULT_CONFIG.dup
        end

        def log(out)
          if out.is_a?(String)
            @config[:log] = File.open(out, "a")
          else
            @config[:log] = out
          end
        end

        def debug(bool)
          @config[:debug] = !!bool
        end

        def listener(type, conf)
          case type
          when :unix
            lc = conf.merge(listener: UNIXListener)
          when :tcp
            lc = conf.merge(listener: TCPListener)
          when :tls
            lc = conf.merge(listener: TLSListener)
          else
            raise "Unknown listener type: #{type} (known type: :unix, :http, :https)"
          end

          @config[:listeners] << lc
        end

        def server_push(bool)
          @config[:server_push] = !!bool
        end
      end
    end
  end
end
