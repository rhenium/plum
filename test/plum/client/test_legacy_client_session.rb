require_relative "../../utils"

using BinaryString
class LegacyClientSessionTest < Test::Unit::TestCase
  def test_empty?
    io = StringIO.new
    session = LegacyClientSession.new(io, Client::DEFAULT_CONFIG)
    assert(session.empty?)
    res = session.request({}, "aa", {})
    assert(!session.empty?)
    io.string << "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
    session.succ
    assert(res.finished?)
    assert(session.empty?)
  end

  def test_close_fails_req
    session = LegacyClientSession.new(StringIO.new, Client::DEFAULT_CONFIG)
    res = session.request({}, nil, {})
    assert(!res.failed?)
    session.close
    assert(res.failed?)
  end

  def test_fail
    io = StringIO.new
    session = LegacyClientSession.new(io, Client::DEFAULT_CONFIG)
    res = session.request({}, "aa", {})
    assert_raises {
      session.succ
    }
    assert(!res.finished?)
    assert(res.failed?)
  end

  def test_request
    io = StringIO.new
    session = LegacyClientSession.new(io, Client::DEFAULT_CONFIG.merge(hostname: "aa"))
    res = session.request({ ":method" => "GET", ":path" => "/aa" }, "aa", {})
    assert_equal("GET /aa HTTP/1.1\r\nhost: aa\r\ntransfer-encoding: chunked\r\n\r\n2\r\naa\r\n", io.string)
    io.string << "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\naaa"
    session.succ until res.finished?
    assert(res.finished?)
    assert_equal("aaa", res.body)
    assert_equal({ ":status" => "200", "content-length" => "3" }, res.headers)
  end

  def test_chunked_chunked_string
    io = StringIO.new
    session = LegacyClientSession.new(io, Client::DEFAULT_CONFIG.merge(hostname: "hostname"))
    session.request({ ":method" => "GET", ":path" => "/aa" }, "a" * 1025, {})
    assert_equal(<<-EOR, io.string)
GET /aa HTTP/1.1\r
host: hostname\r
transfer-encoding: chunked\r
\r
401\r
#{"a"*1025}\r
    EOR
  end

  def test_chunked_chunked_io
    io = StringIO.new
    session = LegacyClientSession.new(io, Client::DEFAULT_CONFIG.merge(hostname: "hostname"))
    session.request({ ":method" => "GET", ":path" => "/aa" }, StringIO.new("a" * 1025), {})
    assert_equal(<<-EOR, io.string)
GET /aa HTTP/1.1\r
host: hostname\r
transfer-encoding: chunked\r
\r
400\r
#{"a"*1024}\r
1\r
a\r
    EOR
  end

  def test_chunked_sized
    io = StringIO.new
    session = LegacyClientSession.new(io, Client::DEFAULT_CONFIG.merge(hostname: "hostname"))
    session.request({ ":method" => "GET", ":path" => "/aa", "content-length" => 1025 }, StringIO.new("a" * 1025), {})
    assert_equal((<<-EOR).chomp, io.string)
GET /aa HTTP/1.1\r
content-length: 1025\r
host: hostname\r
\r
#{"a"*1025}
    EOR
  end
end
