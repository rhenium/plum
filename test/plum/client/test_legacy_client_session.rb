require "test_helper"

using Plum::BinaryString
class LegacyClientSessionTest < Minitest::Test
  def test_empty?
    io = StringIO.new
    session = LegacyClientSession.new(io, Client::DEFAULT_CONFIG)
    assert(session.empty?)
    res = session.request({}, "aa")
    assert(!session.empty?)
    io.string << "HTTP/1.1 200 OK\r\nContent-Length: 0\r\n\r\n"
    session.succ
    assert(res.finished?)
    assert(session.empty?)
  end

  def test_close_fails_req
    session = LegacyClientSession.new(StringIO.new, Client::DEFAULT_CONFIG)
    res = session.request({})
    assert(!res.failed?)
    session.close
    assert(res.failed?)
  end

  def test_fail
    io = StringIO.new
    session = LegacyClientSession.new(io, Client::DEFAULT_CONFIG)
    res = session.request({}, "aa")
    assert_raises {
      session.succ
    }
    assert(!res.finished?)
    assert(res.failed?)
  end

  def test_request
    io = StringIO.new
    session = LegacyClientSession.new(io, Client::DEFAULT_CONFIG.merge(hostname: "aa"))
    res = session.request({ ":method" => "GET", ":path" => "/aa" }, "aa")
    assert("GET /aa HTTP/1.1\r\nhost: aa\r\n\r\naa")
    io.string << "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\naaa"
    session.succ until res.finished?
    assert(res.finished?)
    assert("aaa", res.body)
    assert({ ":status" => "200", "content-length" => "3" }, res.headers)
  end
end
