require "test_helper"

using Plum::BinaryString

class HTTPSConnectionNegotiationTest < Minitest::Test
  def test_server_must_raise_cprotocol_error_invalid_magic_short
    con = ServerConnection.new(StringIO.new.method(:write))
    assert_connection_error(:protocol_error) {
      con << "HELLO"
    }
  end

  def test_server_must_raise_cprotocol_error_invalid_magic_long
    con = ServerConnection.new(StringIO.new.method(:write))
    assert_connection_error(:protocol_error) {
      con << ("HELLO" * 100) # over 24
    }
  end

  def test_server_must_raise_cprotocol_error_non_settings_after_magic
    con = ServerConnection.new(StringIO.new.method(:write))
    con << Connection::CLIENT_CONNECTION_PREFACE
    assert_connection_error(:protocol_error) {
      con << Frame.new(type: :window_update, stream_id: 0, payload: "".push_uint32(1)).assemble
    }
  end

  def test_server_accept_fragmented_magic
    magic = Connection::CLIENT_CONNECTION_PREFACE
    con = ServerConnection.new(StringIO.new.method(:write))
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
    ctx.cert = TLS_CERT
    ctx.key = TLS_KEY
    tcp_server = TCPServer.new("127.0.0.1", LISTEN_PORT)
    ssl_server = OpenSSL::SSL::SSLServer.new(tcp_server, ctx)

    server_thread = Thread.new {
      begin
        Timeout.timeout(3) {
          sock = ssl_server.accept
          plum = SSLSocketServerConnection.new(sock)
          assert_connection_error(:inadequate_security) {
            run = true
            while !sock.closed? && !sock.eof?
              plum << sock.readpartial(1024)
            end
          }
        }
      rescue Timeout::Error
        flunk "server timeout"
      rescue => e
        flunk e
      ensure
        tcp_server.close
      end
    }
    client_thread = Thread.new {
      sock = TCPSocket.new("127.0.0.1", LISTEN_PORT)
      begin
        ctx = OpenSSL::SSL::SSLContext.new.tap { |ctx|
          ctx.alpn_protocols = ["h2"]
          ctx.ciphers = "AES256-GCM-SHA384"
        }
        ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
        ssl.connect
        ssl.write Connection::CLIENT_CONNECTION_PREFACE
        ssl.write Frame.settings.assemble
        sleep
      rescue => e
        flunk e
      ensure
        sock.close
      end
    }
    server_thread.join
    client_thread.kill

    flunk "test not run" unless run
  end
end
