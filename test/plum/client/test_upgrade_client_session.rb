require "test_helper"

using Plum::BinaryString
class UpgradeClientSessionTest < Minitest::Test
  def test_empty?
    sock = StringSocket.new("HTTP/1.1 101\r\n\r\n")
    session = UpgradeClientSession.new(sock, Client::DEFAULT_CONFIG)
    assert(sock.wio.string.start_with?("OPTIONS * HTTP/1.1\r\n"), "sends options request")
    assert(session.empty?)
  end

  def test_close
    sock = StringSocket.new("HTTP/1.1 101\r\n\r\n")
    session = UpgradeClientSession.new(sock, Client::DEFAULT_CONFIG)
    res = session.request({}, nil, {})
    assert(!res.failed?)
    session.close
    assert(res.failed?)
  end

  def test_request
    sock = StringSocket.new("HTTP/1.1 101\r\n\r\n")
    session = UpgradeClientSession.new(sock, Client::DEFAULT_CONFIG)
    sock.rio.string << Frame::Settings.new.assemble
    sock.rio.string << Frame::Settings.ack.assemble
    res = session.request({ ":method" => "GET", ":path" => "/aa" }, "aa", {})
    sock.rio.string << Frame::Headers.new(3, HPACK::Encoder.new(3).encode(":status" => "200", "content-length" => "3"), end_headers: true).assemble
    sock.rio.string << Frame::Data.new(3, "aaa", end_stream: true).assemble
    session.succ until res.finished?
    assert(res.finished?)
    assert_equal("aaa", res.body)
    assert_equal({ ":status" => "200", "content-length" => "3" }, res.headers)
  end

  def test_request_legacy
    sock = StringSocket.new("HTTP/1.1 200\r\nContent-Length: 0\r\n\r\n")
    session = UpgradeClientSession.new(sock, Client::DEFAULT_CONFIG)
    res = session.request({ ":method" => "GET", ":path" => "/aa" }, "aa", {})
    sock.rio.string << "HTTP/1.1 200 OK\r\nContent-Length: 3\r\n\r\naaaHTTP/1.1 400\r\nnext-response"
    session.succ until res.finished?
    assert(res.finished?)
    assert_equal("aaa", res.body)
    assert_equal({ ":status" => "200", "content-length" => "3" }, res.headers)
  end
end
