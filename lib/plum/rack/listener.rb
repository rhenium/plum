module Plum
  module Rack
    class BaseListener
      def stop
        @server.close
      end

      def to_io
        raise "not implemented"
      end

      def accept
        to_io.accept
      end
    end

    class TCPListener < BaseListener
      def initialize(lc)
        @server = ::TCPServer.new(lc[:hostname], lc[:port])
      end

      def to_io
        @server.to_io
      end
    end

    class TLSListener < BaseListener
      def initialize(hostname, port, cert, key)
        ctx = OpenSSL::SSL::SSLContext.new
        ctx.ssl_version = :TLSv1_2
        ctx.alpn_select_cb = -> protocols {
          raise "Client does not support HTTP/2: #{protocols}" unless protocols.include?("h2")
          "h2"
        }
        ctx.tmp_ecdh_callback = -> (sock, ise, keyl) { OpenSSL::PKey::EC.new("prime256v1") }
        ctx.cert = OpenSSL::X509::Certificate.new(cert)
        ctx.key = OpenSSL::PKey::RSA.new(key)
        tcp_server = ::TCPServer.new(hostname, port)
        @server = OpenSSL::SSL::SSLServer.new(tcp_server, ctx)
        @server.start_immediately = false
      end

      def to_io
        @server.to_io
      end
    end

    class UNIXListener < BaseListener
      def initialize(path, permission, user, group)
        @server = ::UNIXServer.new(path)
        # TODO: set permission, user, group
      end

      def to_io
        @server.to_io
      end
    end
  end
end
