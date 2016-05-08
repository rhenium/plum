# frozen-string-literal: true

module Plum
  module Rack
    class Server
      attr_reader :config, :app, :logger, :threadpool

      def initialize(app, config)
        @config = config
        @state = :null
        @app = config[:debug] ? ::Rack::CommonLogger.new(app) : app
        @logger = Logger.new(config[:log] || $stdout).tap { |l| l.level = config[:debug] ? Logger::DEBUG : Logger::INFO }
        @listeners = config[:listeners].map { |lc| lc[:listener].new(lc) }
        @threadpool = ThreadPool.new(@config[:threadpool_size]) if @config[:threadpool_size] > 1

        @logger.info("Plum #{::Plum::VERSION}")
        @logger.info("Config: #{config}")

        if @config[:user]
          drop_privileges
        end
      end

      def start
        #trap(:INT) { @state = :ee }
        #require "lineprof"
        #Lineprof.profile(//){
        @state = :running
        while @state == :running && !@listeners.empty?
          begin
            if ss = IO.select(@listeners, nil, nil, 2.0)
              ss[0].each { |svr|
                begin
                  svr.accept(self)
                rescue Errno::ECONNRESET, Errno::ECONNABORTED # closed
                rescue
                  log_exception $!
                end
              }
            end
          rescue Errno::EBADF # closed
          rescue
            log_exception $!
          end
        end
        #}
      end

      def stop
        @state = :stop
        @listeners.map(&:stop)
        # TODO: gracefully shutdown connections (wait threadpool?)
      end

      def log_exception(e)
        @logger.error("#{e.class}: #{e.message}\n#{e.backtrace.map { |b| "\t#{b}" }.join("\n")}")
      end

      private
      def drop_privileges
        begin
          user = @config[:user]
          group = @config[:group] || user
          @logger.info "Dropping process privilege to #{user}:#{group}"

          cuid, cgid = Process.euid, Process.egid
          tuid, tgid = Etc.getpwnam(user).uid, Etc.getgrnam(group).gid

          Process.initgroups(user, tgid)
          Process::GID.change_privilege(tgid)
          Process::UID.change_privilege(tuid)
        rescue Errno::EPERM => e
          @ogger.fatal "Could not change privilege: #{e}"
          exit 2
        end
      end
    end
  end
end
