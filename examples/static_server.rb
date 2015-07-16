$LOAD_PATH << File.expand_path("../../lib", __FILE__)
require "plum"
require "openssl"
require "socket"
require "cgi"

begin
  require "sslkeylog/autotrace" # for debug
rescue
end

def log(con, stream, s)
  prefix = "[%02x;%02x] " % [con, stream]
  if s.is_a?(Enumerable)
    puts s.map {|a| prefix + a.to_s }.join("\n")
  else
    puts prefix + s.to_s
  end
end

ctx = OpenSSL::SSL::SSLContext.new
ctx.alpn_select_cb = -> protocols {
  raise "Client does not support HTTP/2." unless protocols.include?("h2")
  "h2"
}
ctx.cert = OpenSSL::X509::Certificate.new File.read(".crt.local")
ctx.key = OpenSSL::PKey::RSA.new File.read(".key.local")
tcp_server = TCPServer.new("0.0.0.0", 40443)
ssl_server = OpenSSL::SSL::SSLServer.new(tcp_server, ctx)

loop do
  begin
    sock = ssl_server.accept
    id = sock.io.fileno
    puts "#{id}: accept!"
  rescue => e
    puts e
    next
  end

  plum = Plum::Server.new(sock)

  plum.on_frame = proc do |frame|
    log(id, frame.stream_id, "recv: #{frame.inspect}")
  end

  plum.on_send_frame = proc do |frame|
    log(id, frame.stream_id, "send: #{frame.inspect}")
  end

  plum.on_stream = proc do |stream|
    headers = data = nil

    stream.on_open = proc do
      headers = nil
      data = ""
    end

    stream.on_headers = proc do |headers_|
      log(id, stream.id, headers_.map {|name, value| "#{name}: #{value}" })
      headers = headers_
    end

    stream.on_data = proc do |data_|
      log(id, stream.id, data_)
      data << data_
    end

    stream.on_complete = proc do
      case [headers[":method"], headers[":path"]]
      when ["GET", "/"]
        body = "Hello World! <a href=/abc.html>ABC</a> <a href=/fgsd>Not found</a>"
        body << <<-EOF
        <form action=post.page method=post>
        <input type=text name=key value=default_value>
        <input type=submit>
        </form>
        EOF
        stream.send_headers({
          ":status": "200",
          "server": "plum",
          "content-type": "text/html",
          "content-length": body.size
        })
        stream.send_body(body, [:end_stream])
      when ["GET", "/abc.html"]
        body = "ABC! <a href=/>Back to top page</a>"
        stream.send_headers({
          ":status": "200",
          "server": "plum",
          "content-type": "text/html",
          "content-length": body.size
        })
        stream.send_body(body, [:end_stream])
      when ["POST", "/post.page"]
        body = "Posted value is: #{CGI.unescape(data).gsub("<", "&lt;").gsub(">", "&gt;")}<br> <a href=/>Back to top page</a>"
        stream.send_headers({
          ":status": "200",
          "server": "plum",
          "content-type": "text/html",
          "content-length": body.size
        })
        stream.send_body(body, [:end_stream])
      else
        body = "Page not found! <a href=/>Back to top page</a>"
        stream.send_headers({
          ":status": "404",
          "server": "plum",
          "content-type": "text/html",
          "content-length": body.size
        })
        stream.send_body(body, [:end_stream])
      end
    end
  end

  Thread.new {
    begin
      plum.start
    rescue
      puts $!
      puts $!.backtrace
    end
  }
end
