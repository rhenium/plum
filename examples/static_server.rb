# frozen-string-literal: true

$LOAD_PATH << File.expand_path("../../lib", __FILE__)
require "plum"
require "openssl"
require "socket"
require "cgi"

begin
  require "sslkeylog/autotrace"
rescue LoadError
end

def log(con, stream, s)
  prefix = "[%02x;%02x] " % [con, stream]
  if s.is_a?(Enumerable)
    puts s.map { |a| prefix + a.to_s }.join("\n")
  else
    puts prefix + s.to_s
  end
end

ctx = OpenSSL::SSL::SSLContext.new
ctx.ssl_version = :TLSv1_2
ctx.alpn_select_cb = -> protocols {
  raise "Client does not support HTTP/2: #{protocols}" unless protocols.include?("h2")
  "h2"
}
if ctx.respond_to?(:tmp_ecdh_callback) && !ctx.respond_to?(:set_ecdh_curves)
  ctx.tmp_ecdh_callback = -> (sock, ise, keyl) {
    OpenSSL::PKey::EC.new("prime256v1")
  }
end
ctx.cert = OpenSSL::X509::Certificate.new File.read(File.expand_path("../../test/server.crt", __FILE__))
ctx.key = OpenSSL::PKey::RSA.new File.read(File.expand_path("../../test/server.key", __FILE__))
tcp_server = TCPServer.new("0.0.0.0", 40443)
ssl_server = OpenSSL::SSL::SSLServer.new(tcp_server, ctx)

loop do
  begin
    sock = ssl_server.accept
    id = sock.io.fileno
    puts "#{id}: accept! #{sock.cipher.inspect}"
  rescue
    STDERR.puts $!
    next
  end

  plum = Plum::ServerConnection.new(sock.method(:write))

  plum.on(:frame) do |frame|
    log(id, frame.stream_id, "recv: #{frame.inspect}")
  end

  plum.on(:send_frame) do |frame|
    log(id, frame.stream_id, "send: #{frame.inspect}")
  end

  plum.on(:connection_error) do |exception|
    puts exception
    puts exception.backtrace
  end

  plum.on(:stream) do |stream|
    stream.on(:stream_error) do |exception|
      puts exception
      puts exception.backtrace
    end

    stream.on(:send_deferred) do |frame|
      log(id, frame.stream_id, "send (deferred): #{frame.inspect}")
    end

    headers = data = nil

    stream.on(:open) do
      headers = nil
      data = "".b
    end

    stream.on(:headers) do |headers_|
      log(id, stream.id, headers_.map { |name, value| "#{name}: #{value}" })
      headers = headers_.to_h
    end

    stream.on(:data) do |data_|
      log(id, stream.id, data_)
      data << data_
    end

    stream.on(:end_stream) do
      case [headers[":method"], headers[":path"]]
      when ["GET", "/"]
        body = <<-EOF
        Hello World! <a href=/abc.html>ABC</a> <a href=/fgsd>Not found</a>
        <form action=post.page method=post>
        <input type=text name=key value=default_value>
        <input type=submit>
        </form>
        EOF
        stream.send_headers({
          ":status": "200",
          "server": "plum",
          "content-type": "text/html",
          "content-length": body.bytesize
        }, end_stream: false)
        stream.send_data(body, end_stream: true)
      when ["GET", "/abc.html"]
        body = "ABC! <a href=/>Back to top page</a><br><img src=/image.nyan>"
        stream.send_headers({
          ":status": "200",
          "server": "plum",
          "content-type": "text/html",
          "content-length": body.bytesize
        }, end_stream: false)
        i_stream = stream.promise({
          ":authority": "localhost:40443",
          ":method": "GET",
          ":scheme": "https",
          ":path": "/image.nyan"
        })
        stream.send_data(body, end_stream: true)
        image = ("iVBORw0KGgoAAAANSUhEUgAAAEAAAABAAgMAAADXB5lNAAAACVBMVEX///93o0jG/4mTMy20AAAA" \
                 "bklEQVQ4y2NgoAoIRQJkCoSimIdTgJGBBU1ABE1A1AVdBQuaACu6gCALhhZ0axlZCDgMWYAB6ilU" \
                 "35IoADEMxWyyBDD45AhQCFahM0kXWIVu3sAJrILzyBcgytoFeATABBcXWohhCEC14BCgGAAAX1ZQ" \
                 "ZtJp0zAAAAAASUVORK5CYII=").unpack("m")[0]
        i_stream.send_headers({
          ":status": "200",
          "server": "plum",
          "content-type": "image/png",
          "content-length": image.bytesize
        }, end_stream: false)
        i_stream.send_data(image, end_stream: true)
      when ["POST", "/post.page"]
        body = "Posted value is: #{CGI.unescape(data).gsub("<", "&lt;").gsub(">", "&gt;")}<br> <a href=/>Back to top page</a>"
        stream.send_headers({
          ":status": "200",
          "server": "plum",
          "content-type": "text/html",
          "content-length": body.bytesize
        }, end_stream: false)
        stream.send_data(body, end_stream: true)
      else
        body = "Page not found! <a href=/>Back to top page</a>"
        stream.send_headers({
          ":status": "404",
          "server": "plum",
          "content-type": "text/html",
          "content-length": body.bytesize
        }, end_stream: false)
        stream.send_data(body, end_stream: true)
      end
    end
  end

  Thread.new {
    begin
      while !sock.closed? && !sock.eof?
        plum << sock.readpartial(1024)
      end
    rescue
      puts $!
      puts $!.backtrace
    ensure
      sock.close
    end
  }
end
