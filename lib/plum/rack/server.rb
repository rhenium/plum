# -*- frozen-string-literal: true -*-
module Plum
  module Rack
    class Server
      attr_reader :config

      def initialize(app, config)
        @config = config
        @state = :null
        @app = config[:debug] ? ::Rack::CommonLogger.new(app) : app
        @logger = Logger.new(config[:log] || $stdout).tap { |l|
          l.level = config[:debug] ? Logger::DEBUG : Logger::INFO
        }
        @listeners = config[:listeners].map { |lc|
          lc[:listener].new(lc)
        }

        @logger.info("Plum #{::Plum::VERSION}")
        @logger.info("Config: #{config}")
      end

      def start
        @state = :running
        while @state == :running
          break if @listeners.empty?
          begin
            if ss = IO.select(@listeners, nil, nil, 2.0)
              ss[0].each { |svr|
                new_con(svr)
              }
            end
          rescue Errno::EBADF, Errno::ENOTSOCK, IOError => e # closed
          rescue StandardError => e
            log_exception(e)
          end
        end
      end

      def stop
        @state = :stop
        @listeners.map(&:stop)
        # TODO: gracefully shutdown connections
      end

      private
      def new_con(svr)
        sock = svr.accept
        Thread.new {
          begin
            begin
              sock = sock.accept if sock.respond_to?(:accept)
              plum = svr.plum(sock)

              con = Session.new(app: @app,
                                plum: plum,
                                sock: sock,
                                logger: @logger,
                                config: @config,
                                remote_addr: sock.peeraddr.last)
              con.run
            rescue ::Plum::LegacyHTTPError => e
              @logger.info "legacy HTTP client: #{e}"
              handle_legacy(e, sock)
            end
          rescue Errno::ECONNRESET, Errno::EPROTO, Errno::EINVAL, EOFError => e # closed
          rescue StandardError => e
            log_exception(e)
          ensure
            sock.close if sock
          end
        }
      rescue Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINVAL => e # closed
        sock.close if sock
      rescue StandardError => e
        log_exception(e)
        sock.close if sock
      end

      def log_exception(e)
        @logger.error("#{e.class}: #{e.message}\n#{e.backtrace.map { |b| "\t#{b}" }.join("\n")}")
      end

      def handle_legacy(e, sock)
        if @config[:fallback_legacy_host]
          @logger.info "legacy HTTP: fallbacking to: #{@config[:fallback_legacy_host]}:#{@config[:fallback_legacy_port]}"
          upstream = TCPSocket.open(@config[:fallback_legacy_host], @config[:fallback_legacy_port])
          upstream.write(e.buf) if e.buf
          loop do
            ret = IO.select([sock, upstream])
            ret[0].each { |s|
              a = s.readpartial(65536)
              if s == upstream
                sock.write(a)
              else
                upstream.write(a)
              end
            }
          end
        end
      ensure
        upstream.close if upstream
      end
    end
  end
end
