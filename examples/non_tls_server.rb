$LOAD_PATH << File.expand_path("../../lib", __FILE__)
require "plum"
require "socket"
require "cgi"

def log(con, stream, s)
  prefix = "[%02x;%02x] " % [con, stream]
  if s.is_a?(Enumerable)
    puts s.map {|a| prefix + a.to_s }.join("\n")
  else
    puts prefix + s.to_s
  end
end

tcp_server = TCPServer.new("0.0.0.0", 40080)

loop do
  begin
    sock = tcp_server.accept
    id = sock.fileno
    puts "#{id}: accept!"
  rescue => e
    STDERR.puts e
    next
  end

  plum = Plum::HTTPConnection.new(sock)

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
      data = ""
    end

    stream.on(:headers) do |headers_|
      log(id, stream.id, headers_.map {|name, value| "#{name}: #{value}" })
      headers = headers_.to_h
    end

    stream.on(:data) do |data_|
      log(id, stream.id, data_)
      data << data_
    end

    stream.on(:end_stream) do
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
      plum.run
    rescue
      puts $!
      puts $!.backtrace
    ensure
      sock.close
    end
  }
end