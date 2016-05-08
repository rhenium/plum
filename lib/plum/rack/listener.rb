# frozen-string-literal: true

module Plum
  module Rack
    class BaseListener
      def stop
        @server.close
      end

      def to_io
        raise "not implemented"
      end

      def accept(svc)
        raise "not implemented"
      end

      def method_missing(name, *args)
        @server.__send__(name, *args)
      end
    end

    class TCPListener < BaseListener
      def initialize(lc)
        @server = ::TCPServer.new(lc[:hostname], lc[:port])
      end

      def to_io
        @server.to_io
      end

      def accept(svc)
        sock = @server.accept
        Thread.start {
          begin
            plum = ::Plum::HTTPServerConnection.new(sock.method(:write))
            sess = Session.new(svc, sock, plum)
            sess.run
          rescue ::Plum::LegacyHTTPError => e
            svc.logger.info "legacy HTTP client: #{e}"
            sess = LegacySession.new(svc, e, sock)
            sess.run
          rescue Errno::ECONNRESET, Errno::ECONNABORTED, EOFError # closed
          rescue
            svc.log_exception $!
          ensure
            sock.close
          end
        }
      end
    end

    class TLSListener < BaseListener
      def initialize(lc)
        if lc[:certificate] && lc[:certificate_key]
          cert = File.read(lc[:certificate])
          key = File.read(lc[:certificate_key])
        else
          STDERR.puts "WARNING: using dummy certificate"
          cert, key = dummy_key
        end

        ctx = OpenSSL::SSL::SSLContext.new
        ctx.ssl_version = :TLSv1_2
        ctx.alpn_select_cb = -> (protocols) { protocols.include?("h2") ? "h2" : protocols.first }
        ctx.tmp_ecdh_callback = -> (sock, ise, keyl) { OpenSSL::PKey::EC.new("prime256v1") }
        *ctx.extra_chain_cert, ctx.cert = parse_chained_cert(cert)
        ctx.key = OpenSSL::PKey::RSA.new(key)
        ctx.servername_cb = proc { |sock, hostname|
          if host = lc[:sni]&.[](hostname)
            new_ctx = ctx.dup
            *new_ctx.extra_chain_cert, new_ctx.cert = parse_chained_cert(File.read(host[:certificate]))
            new_ctx.key = OpenSSL::PKey::RSA.new(File.read(host[:certificate_key]))
            new_ctx
          else
            ctx
          end
        }
        tcp_server = ::TCPServer.new(lc[:hostname], lc[:port])
        @server = OpenSSL::SSL::SSLServer.new(tcp_server, ctx)
        @server.start_immediately = false # call socket#accept twice: [tcp, tls]
      end

      def parse_chained_cert(str)
        str.scan(/-----BEGIN CERTIFICATE.+?END CERTIFICATE-----/m).map { |s| OpenSSL::X509::Certificate.new(s) }
      end

      def to_io
        @server.to_io
      end

      def accept(svc)
        sock = @server.accept
        Thread.start {
          begin
            sock = sock.accept
            raise ::Plum::LegacyHTTPError.new("client didn't offer h2 with ALPN", nil) unless sock.alpn_protocol == "h2"
            plum = ::Plum::ServerConnection.new(sock.method(:write))
            sess = Session.new(svc, sock, plum)
            sess.run
          rescue ::Plum::LegacyHTTPError => e
            svc.logger.info "legacy HTTP client: #{e}"
            sess = LegacySession.new(svc, e, sock)
            sess.run
          rescue Errno::ECONNRESET, Errno::ECONNABORTED, EOFError # closed
          rescue
            svc.log_exception $!
          ensure
            sock.close if sock
          end
        }
      end

      private
      # returns: [cert, key]
      def dummy_key
        STDERR.puts "WARNING: Generating new dummy certificate..."

        key = OpenSSL::PKey::RSA.new(2048)
        cert = OpenSSL::X509::Certificate.new
        cert.subject = cert.issuer = OpenSSL::X509::Name.parse("/C=JP/O=Test/OU=Test/CN=example.com")
        cert.not_before = Time.now
        cert.not_after = Time.now + 363 * 24 * 60 * 60
        cert.public_key = key.public_key
        cert.serial = rand((1 << 20) - 1)
        cert.version = 2

        ef = OpenSSL::X509::ExtensionFactory.new
        ef.subject_certificate = cert
        ef.issuer_certificate = cert
        cert.extensions = [
          ef.create_extension("basicConstraints", "CA:TRUE", true),
        ]
        cert.sign(key, OpenSSL::Digest::SHA256.new)

        [cert.to_s, key.to_s]
      end
    end

    class UNIXListener < BaseListener
      def initialize(lc)
        if File.exist?(lc[:path])
          begin
            old = UNIXSocket.new(lc[:path])
          rescue SystemCallError, IOError
            File.unlink(lc[:path])
          else
            old.close
            raise "Already a server bound to: #{lc[:path]}"
          end
        end

        @server = ::UNIXServer.new(lc[:path])

        File.chmod(lc[:mode], lc[:path]) if lc[:mode]
      end

      def stop
        super
        File.unlink(lc[:path])
      end

      def to_io
        @server.to_io
      end

      def accept(svc)
        sock = @server.accept
        Thread.start {
          begin
            plum = ::Plum::ServerConnection.new(sock.method(:write))
            sess = Session.new(svc, sock, plum)
            sess.run
          rescue Errno::ECONNRESET, Errno::ECONNABORTED, EOFError # closed
          rescue
            svc.log_exception $!
          ensure
            sock.close if sock
          end
        }
      end
    end
  end
end
