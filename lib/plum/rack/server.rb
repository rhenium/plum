module Plum
  module Rack
    class Server
      def initialize(app, config)
        @state = :null
        @app = config[:debug] ? ::Rack::CommonLogger.new(app) : app
        @logger = Logger.new(config[:log] || $stdout).tap { |l|
          l.level = config[:debug] ? Logger::DEBUG : Logger::INFO
        }
        @listeners = config[:listeners].map { |lc|
          lc[:listener].new(lc)
        }

        @logger.info("Plum::Rack #{::Plum::Rack::VERSION} (Plum #{::Plum::VERSION})")
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
            @logger.debug("socket closed?: #{e}")
          rescue StandardError => e
            @logger.error("#{e.class}: #{e.message}\n#{e.backtrace.map { |b| "\t#{b}" }.join("\n")}")
          end
        end
      end

      def stop
        @state = :stop
        @listeners.map(&:stop)
      end

      private
      def new_con(svr)
        sock = svr.accept
        @logger.debug("accept: #{sock}")

        con = Connection.new(@app, sock, @logger)
        con.start
      rescue Errno::ECONNRESET, Errno::ECONNABORTED, Errno::EPROTO, Errno::EINVAL => e # closed
        @logger.debug("connection closed while accepting: #{e}")
      rescue StandardError => e
        @logger.error("#{e.class}: #{e.message}\n#{e.backtrace.map { |b| "\t#{b}" }.join("\n")}")
      end
    end
  end
end
