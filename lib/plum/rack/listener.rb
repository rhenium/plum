# -*- frozen-string-literal: true -*-
module Plum
  module Rack
    class BaseListener
      def stop
        @server.close
      end

      def to_io
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

      def plum(sock)
        ::Plum::HTTPServerConnection.new(sock)
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
        ctx.alpn_select_cb = -> protocols {
          raise "Client does not support HTTP/2: #{protocols}" unless protocols.include?("h2")
          "h2"
        }
        ctx.tmp_ecdh_callback = -> (sock, ise, keyl) { OpenSSL::PKey::EC.new("prime256v1") }
        ctx.cert = OpenSSL::X509::Certificate.new(cert)
        ctx.key = OpenSSL::PKey::RSA.new(key)
        tcp_server = ::TCPServer.new(lc[:hostname], lc[:port])
        @server = OpenSSL::SSL::SSLServer.new(tcp_server, ctx)
        @server.start_immediately = false
      end

      def to_io
        @server.to_io
      end

      def plum(sock)
        ::Plum::HTTPSServerConnection.new(sock)
      end

      private
      # returns: [cert, key]
      def dummy_key
        puts "WARNING: Generating new dummy certificate..."

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
          ef.create_extension("subjectKeyIdentifier", "hash"),
        ]
        cert.add_extension ef.create_extension("authorityKeyIdentifier", "keyid:always,issuer:always")

        cert.sign key, OpenSSL::Digest::SHA1.new

        [cert, key]
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

      def plum(sock)
        ::Plum::HTTPSServerConnection.new(sock)
      end
    end
  end
end
