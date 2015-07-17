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
  raise "Client does not support HTTP/2: #{protocols}" unless protocols.include?("h2")
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

  plum = Plum::ServerConnection.new(sock)

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

    headers = data = nil

    stream.on(:open) do
      headers = nil
      data = ""
    end

    stream.on(:headers) do |headers_|
      log(id, stream.id, headers_.map {|name, value| "#{name}: #{value}" })
      headers = headers_
    end

    stream.on(:data) do |data_|
      log(id, stream.id, data_)
      data << data_
    end

    stream.on(:complete) do
      case [headers[":method"], headers[":path"]]
      when ["GET", "/"]
        body = "Hello World! <a href=/abc.html>ABC</a> <a href=/fgsd>Not found</a>"
        body << <<-EOF
        <form action=post.page method=post>
        <input type=text name=key value=default_value>
        <input type=submit>
        </form>
        EOF
        stream.respond({
          ":status": "200",
          "server": "plum",
          "content-type": "text/html",
          "content-length": body.size
        }, body)
      when ["GET", "/abc.html"]
        body = "ABC! <a href=/>Back to top page</a><br><img src=/image.nyan>"
        i_stream = stream.promise({
          ":authority": "localhost:40443",
          ":method": "GET",
          ":scheme": "https",
          ":path": "/image.nyan"
        })
        stream.respond({
          ":status": "200",
          "server": "plum",
          "content-type": "text/html",
          "content-length": body.size
        }, body)
        image = ("iVBORw0KGgoAAAANSUhEUgAAAEAAAABAAgMAAADXB5lNAAAACVBMVEX///93o0jG/4mTMy20AAAA" <<
                 "bklEQVQ4y2NgoAoIRQJkCoSimIdTgJGBBU1ABE1A1AVdBQuaACu6gCALhhZ0axlZCDgMWYAB6ilU" <<
                 "35IoADEMxWyyBDD45AhQCFahM0kXWIVu3sAJrILzyBcgytoFeATABBcXWohhCEC14BCgGAAAX1ZQ" <<
                 "ZtJp0zAAAAAASUVORK5CYII=").unpack("m")[0]
        i_stream.respond({
          ":status": "200",
          "server": "plum",
          "content-type": "image/png",
          "content-length": image.size
        }, image)
      when ["POST", "/post.page"]
        body = "Posted value is: #{CGI.unescape(data).gsub("<", "&lt;").gsub(">", "&gt;")}<br> <a href=/>Back to top page</a>"
        stream.respond({
          ":status": "200",
          "server": "plum",
          "content-type": "text/html",
          "content-length": body.size
        }, body)
      else
        body = "Page not found! <a href=/>Back to top page</a>"
        stream.respond({
          ":status": "404",
          "server": "plum",
          "content-type": "text/html",
          "content-length": body.size
        }, body)
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
