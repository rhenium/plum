require "test_helper"

using Plum::BinaryString

class HTTPConnectionNegotiationTest < Minitest::Test
  ## with Prior Knowledge (same as over TLS)
  def test_server_must_raise_cprotocol_error_non_settings_after_magic
    con = HTTPConnection.new(StringIO.new)
    con << Connection::CLIENT_CONNECTION_PREFACE
    assert_connection_error(:protocol_error) {
      con << Frame.new(type: :window_update, stream_id: 0, payload: "".push_uint32(1)).assemble
    }
  end

  def test_server_accept_fragmented_magic
    magic = Connection::CLIENT_CONNECTION_PREFACE
    con = HTTPConnection.new(StringIO.new)
    assert_no_error {
      con << magic[0...5]
      con << magic[5..-1]
      con << Frame.new(type: :settings, stream_id: 0).assemble
    }
  end

  ## with HTTP/1.1 Upgrade
  def test_server_accept_upgrade
    io = StringIO.new
    con = HTTPConnection.new(io)
    heads = nil
    con.on(:stream) {|stream|
      stream.on(:headers) {|_h| heads = _h.to_h }
    }
    req = "GET / HTTP/1.1\r\n" <<
          "Host: rhe.jp\r\n" <<
          "User-Agent: nya\r\n" <<
          "Upgrade: h2c\r\n" <<
          "Connection: HTTP2-Settings, Upgrade\r\n" <<
          "HTTP2-Settings: \r\n" <<
          "\r\n"
    con << req
    assert(io.string.include?("HTTP/1.1 101 "), "Response is not HTTP/1.1 101: #{io.string}")
    assert_no_error {
      con << Connection::CLIENT_CONNECTION_PREFACE
      con << Frame.new(type: :settings, stream_id: 0).assemble
    }
    assert_equal(:half_closed_remote, con.streams[1].state)
    assert_equal({ ":method" => "GET", ":path" => "/", ":authority" => "rhe.jp", "user-agent" => "nya"}, heads)
  end

  def test_server_deny_non_upgrade
    io = StringIO.new
    con = HTTPConnection.new(io)
    req = "GET / HTTP/1.1\r\n" <<
          "Host: rhe.jp\r\n" <<
          "User-Agent: nya\r\n" <<
          "Connection: close\r\n" <<
          "\r\n"
    assert_raises(LegacyHTTPError) {
      con << req
    }
  end
end
