require "test_helper"

using Plum::BinaryString

class HTTPSConnectionNegotiationTest < Minitest::Test
  def test_server_must_raise_cprotocol_error_invalid_magic_short
    con = HTTPSConnection.new(StringIO.new)
    assert_connection_error(:protocol_error) {
      con << "HELLO"
    }
  end

  def test_server_must_raise_cprotocol_error_invalid_magic_long
    con = HTTPSConnection.new(StringIO.new)
    assert_connection_error(:protocol_error) {
      con << ("HELLO" * 100) # over 24
    }
  end

  def test_server_must_raise_cprotocol_error_non_settings_after_magic
    con = HTTPSConnection.new(StringIO.new)
    con << Connection::CLIENT_CONNECTION_PREFACE
    assert_connection_error(:protocol_error) {
      con << Frame.new(type: :window_update, stream_id: 0, payload: "".push_uint32(1)).assemble
    }
  end

  def test_server_accept_fragmented_magic
    magic = Connection::CLIENT_CONNECTION_PREFACE
    con = HTTPSConnection.new(StringIO.new)
    assert_no_error {
      con << magic[0...5]
      con << magic[5..-1]
      con << Frame.new(type: :settings, stream_id: 0).assemble
    }
  end

  def test_inadequate_security_ssl_socket
    run = false

    ctx = OpenSSL::SSL::SSLContext.new
    ctx.alpn_select_cb = -> protocols { "h2" }
    ctx.cert = OpenSSL::X509::Certificate.new File.read(File.expand_path("../../server.crt", __FILE__))
    ctx.key = OpenSSL::PKey::RSA.new File.read(File.expand_path("../../server.key", __FILE__))
    tcp_server = TCPServer.new("127.0.0.1", LISTEN_PORT)
    ssl_server = OpenSSL::SSL::SSLServer.new(tcp_server, ctx)

    server_thread = Thread.new {
      begin
        Timeout.timeout(3) {
          sock = ssl_server.accept
          plum = HTTPSConnection.new(sock)
          assert_connection_error(:inadequate_security) {
            run = true
            plum.run
          }
        }
      rescue Timeout::Error
        flunk "server timeout"
      ensure
        tcp_server.close
      end
    }
    client_thread = Thread.new {
      sock = TCPSocket.new("127.0.0.1", LISTEN_PORT)
      begin
        Timeout.timeout(3) {
          ctx = OpenSSL::SSL::SSLContext.new.tap {|ctx|
            ctx.alpn_protocols = ["h2"]
            ctx.ciphers = "AES256-GCM-SHA384"
          }
          ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
          ssl.connect
          ssl.write Connection::CLIENT_CONNECTION_PREFACE
          ssl.write Frame.settings.assemble
        }
      rescue Timeout::Error
        flunk "client timeout"
      ensure
        sock.close
      end
    }
    client_thread.join
    server_thread.join

    flunk "test not run" unless run
  end
end
