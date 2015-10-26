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
            sock = sock.accept if sock.respond_to?(:accept)
            plum = svr.plum(sock)

            con = Connection.new(app: @app,
                                 plum: plum,
                                 logger: @logger,
                                 server_push: @config[:server_push],
                                 remote_addr: sock.peeraddr.last)
            con.run
          rescue Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINVAL => e # closed
            sock.close if sock
          rescue StandardError => e
            log_exception(e)
            sock.close if sock
          end
        }
      rescue Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINVAL => e # closed
      rescue StandardError => e
        log_exception(e)
      end

      def log_exception(e)
        @logger.error("#{e.class}: #{e.message}\n#{e.backtrace.map { |b| "\t#{b}" }.join("\n")}")
      end
    end
  end
end
