DEBUG = ENV["DEBUG"] || false
HOST = ENV["HOST"]
PORT = ENV["PORT"]
DOCUMENT_ROOT = ENV["DOCUMENT_ROOT"] || "/srv/http"
TLS_CERT = ENV["TLS_CERT"]
TLS_KEY = ENV["TLS_KEY"]

CONTENT_TYPES = {
  /\.html$/ => "text/html",
  /\.png$/ => "image/png",
  /\.jpg$/ => "image/jpeg",
  /\.css$/ => "text/css",
  /\.js$/ => "application/javascript",
}

$LOAD_PATH << File.expand_path("../../lib", __FILE__)
require "plum"
require "openssl"
require "socket"
begin
  require "oga"
  HAVE_OGA = true
rescue LoadError
  puts "Oga is needed for parsing HTML"
  HAVE_OGA = false
end

begin
  require "sslkeylog/autotrace" # for debug
rescue LoadError
end

def log(con, stream, s)
  prefix = "[%02x;%02x] " % [con, stream]
  if s.is_a?(Enumerable)
    puts s.map {|a| prefix + a.to_s }.join("\n")
  else
    puts prefix + s.to_s
  end
end

def content_type(filename)
  exp, ct = CONTENT_TYPES.lazy.select {|pat, e| pat =~ filename }.first
  ct || "texp/plain"
end

def assets(file)
  if /\.html$/ =~ File.basename(file)
    doc = Oga.parse_html(File.read(file))
    assets = []
    doc.xpath("img").each {|img| assets << img.get("src") }
    doc.xpath("//html/head/link[@rel='stylesheet']").each {|css| assets << css.get("href") }
    doc.xpath("script").each {|js| assets << js.get("src") }
    assets.compact.uniq.map {|path|
      if path.include?("//")
        next nil
      end

      if path.start_with?("/")
        pa = File.expand_path(DOCUMENT_ROOT + path)
      else
        pa = File.expand_path(path, file)
      end
      
      if pa.start_with?(DOCUMENT_ROOT) & File.exist?(pa)
        pa
      else
        nil
      end
    }.compact
  else
    []
  end
end

ctx = OpenSSL::SSL::SSLContext.new
ctx.alpn_select_cb = -> protocols {
  raise "Client does not support HTTP/2: #{protocols}" unless protocols.include?("h2")
  "h2"
}
ctx.cert = OpenSSL::X509::Certificate.new File.read(TLS_CERT)
ctx.key = OpenSSL::PKey::RSA.new File.read(TLS_KEY)
tcp_server = TCPServer.new(HOST, PORT)
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
  end if DEBUG

  plum.on(:send_frame) do |frame|
    log(id, frame.stream_id, "send: #{frame.inspect}")
  end if DEBUG

  plum.on(:connection_error) do |exception|
    puts exception
    puts exception.backtrace
  end if DEBUG

  plum.on(:stream) do |stream|
    log(id, stream.id, "stream open")
    stream.on(:stream_error) do |exception|
      puts exception
      puts exception.backtrace
    end if DEBUG

    headers = data = nil

    stream.on(:open) do
      headers = nil
      data = ""
    end

    stream.on(:headers) do |headers_|
      log(id, stream.id, headers_.map {|name, value| "#{name}: #{value}" }) if @DEBUG
      headers = headers_
    end

    stream.on(:data) do |data_|
      log(id, stream.id, data_) if @DEBUG
      data << data_
    end

    stream.on(:complete) do
      if headers[":method"] == "GET"
        file = File.expand_path(DOCUMENT_ROOT + headers[":path"])
        file << "/index.html" if Dir.exist?(file)
        if file.start_with?(DOCUMENT_ROOT) && File.exist?(file)
          io = File.open(file)
          size = File.stat(file).size
          i_sts = assets(file).map {|asset|
            i_st = stream.promise({
              ":authority": headers[":authority"],
              ":method": "GET",
              ":scheme": "https",
              ":path": asset[DOCUMENT_ROOT.size..-1]
            })
            [i_st, asset]
          }
          stream.respond({
            ":status": "200",
            "server": "plum/#{Plum::VERSION}",
            "content-type": content_type(file),
            "content-length": size
          }, io)
          i_sts.each do |i_st, asset|
            aio = File.open(asset)
            asize = File.stat(asset).size
            i_st.respond({
              ":status": "200",
              "server": "plum/#{Plum::VERSION}",
              "content-type": content_type(asset),
              "content-length": asize
            }, aio)
          end
        else
          body = headers.map {|name, value| "#{name}: #{value}" }.join("\n") + "\n" + data
          stream.respond({
            ":status": "404",
            "server": "plum/#{Plum::VERSION}",
            "content-type": "text/plain",
            "content-length": body.bytesize
          }, body)
        end
      else
        # Not implemented
        body = headers.map {|name, value| "#{name}: #{value}" }.join("\n") << "\n" << data
        stream.respond({
          ":status": "501",
          "server": "plum/#{Plum::VERSION}",
          "content-type": "text/plain",
          "content-length": body.bytesize
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
