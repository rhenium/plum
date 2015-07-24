require "test_helper"

using Plum::BinaryString

class ServerStateTest < Minitest::Test
  def test_server_must_repond_cprotocol_error_on_invalid_magic
    invalid_magic = "HELLO" * 10
    start_server do
      start_client do |sock|
        sock.write(invalid_magic)
        frame =  nil
        loop do
          ret = sock.readpartial(1024)
          frame = Plum::Frame.parse!(ret)
          break if frame.type != :settings # server connection preface
        end
        assert_equal(:goaway, frame.type) # connection error
        assert_equal(0x01, frame.payload.uint32(4)) # protocol error
      end
    end
  end

  private
  # Starts a HTTP/2 server and returns Thread object
  def start_server(server_handler = nil, &blk)
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.alpn_select_cb = -> protocols { "h2" }
    ctx.cert = OpenSSL::X509::Certificate.new File.read(File.expand_path("../server.crt", __FILE__))
    ctx.key = OpenSSL::PKey::RSA.new File.read(File.expand_path("../server.key", __FILE__))
    tcp_server = TCPServer.new("127.0.0.1", LISTEN_PORT)
    ssl_server = OpenSSL::SSL::SSLServer.new(tcp_server, ctx)
    
    server_thread = Thread.new {
      begin
        timeout(3) {
          sock = ssl_server.accept
          plum = Plum::ServerConnection.new(sock)
          server_handler.call(plum) if server_handler
          plum.start
        }
      rescue TimeoutError
        flunk "server timeout"
      ensure
        tcp_server.close
      end
    }
    client_thread = Thread.new {
      begin
        timeout(3) { blk.call }
      rescue TimeoutError
        flunk "client timeout"
      end
    }
    client_thread.join
    server_thread.join
  end

  # Connect to server and returns client socket
  def start_client(ctx = nil, &blk)
    ctx ||= OpenSSL::SSL::SSLContext.new.tap {|ctx|
      ctx.alpn_protocols = ["h2"]
    }

    sock = TCPSocket.new("127.0.0.1", LISTEN_PORT)
    ssl = OpenSSL::SSL::SSLSocket.new(sock, ctx)
    ssl.connect
    blk.call(ssl)
  ensure
    ssl.close
  end
end
