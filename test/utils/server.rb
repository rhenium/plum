require "timeout"

module ServerUtils
  def open_server_connection
    io = StringIO.new
    @_con = ServerConnection.new(io)
    @_con << ServerConnection::CLIENT_CONNECTION_PREFACE
    @_con << Frame.new(type: :settings, stream_id: 0).assemble
    if block_given?
      yield @_con
    else
      @_con
    end
  end

  def open_new_stream(state = :idle)
    open_server_connection do |con|
      @_stream = con.instance_eval { new_stream(3, state: state) }
      if block_given?
        yield @_stream
      else
        @_stream
      end
    end
  end

  def sent_frames(con = nil)
    resp = (con || @_con).socket.string.dup
    frames = []
    while f = Frame.parse!(resp)
      frames << f
    end
    frames
  end

  def start_server(&blk)
    ctx = OpenSSL::SSL::SSLContext.new
    ctx.alpn_select_cb = -> protocols { "h2" }
    ctx.cert = OpenSSL::X509::Certificate.new File.read(File.expand_path("../../server.crt", __FILE__))
    ctx.key = OpenSSL::PKey::RSA.new File.read(File.expand_path("../../server.key", __FILE__))
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
end

class Minitest::Test
  include ServerUtils
end
