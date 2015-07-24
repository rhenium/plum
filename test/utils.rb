def start_server(&blk)
  ctx = OpenSSL::SSL::SSLContext.new
  ctx.alpn_select_cb = -> protocols { "h2" }
  ctx.cert = OpenSSL::X509::Certificate.new File.read(File.expand_path("../server.crt", __FILE__))
  ctx.key = OpenSSL::PKey::RSA.new File.read(File.expand_path("../server.key", __FILE__))
  tcp_server = TCPServer.new("127.0.0.1", LISTEN_PORT)
  ssl_server = OpenSSL::SSL::SSLServer.new(tcp_server, ctx)
  
  plum = Plum::ServerConnection.new(nil)

  server_thread = Thread.new {
    begin
      timeout(3) {
        sock = ssl_server.accept
        plum.instance_eval { @socket = sock }
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
      timeout(3) { blk.call(plum) }
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
