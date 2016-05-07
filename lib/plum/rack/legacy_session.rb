# frozen-string-literal: true

using Plum::BinaryString

module Plum
  module Rack
    class LegacySession
      def initialize(svc, e, sock)
        @svc = svc
        @e = e
        @sock = sock
        @config = svc.config
      end

      def run
        if @config[:fallback_legacy_host]
          @svc.logger.info "legacy HTTP: fallbacking to: #{@config[:fallback_legacy_host]}:#{@config[:fallback_legacy_port]}"
          upstream = TCPSocket.open(@config[:fallback_legacy_host], @config[:fallback_legacy_port])
          upstream.write(@e.buf) if @e.buf
          loop do
            ret = IO.select([@sock, upstream])
            ret[0].each { |s|
              a = s.readpartial(65536)
              if s == upstream
                @sock.write(a)
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
