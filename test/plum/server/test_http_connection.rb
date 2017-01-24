require_relative "../../utils"

using BinaryString
class HTTPConnectionNegotiationTest < Test::Unit::TestCase
  ## with Prior Knowledge (same as over TLS)
  def test_server_must_raise_cprotocol_error_non_settings_after_magic
    io = StringIO.new
    con = HTTPServerConnection.new(io.method(:write))
    con << Connection::CLIENT_CONNECTION_PREFACE
    assert_connection_error(:protocol_error) {
      con << Frame::WindowUpdate.new(0, 1).assemble
    }
  end

  def test_server_accept_fragmented_magic
    magic = Connection::CLIENT_CONNECTION_PREFACE
    io = StringIO.new
    con = HTTPServerConnection.new(io.method(:write))
    assert_no_error {
      con << magic[0...5]
      con << magic[5..-1]
      con << Frame::Settings.new.assemble
    }
  end

  ## with HTTP/1.1 Upgrade
  def test_server_accept_upgrade
    io = StringIO.new
    con = HTTPServerConnection.new(io.method(:write))
    heads = nil
    con.on(:headers) { |_, _h| heads = _h.to_h }
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
      con << Frame::Settings.new.assemble
    }
    assert_equal(:half_closed_remote, con.streams[1].state)
    assert_equal({ ":method" => "GET", ":path" => "/", ":authority" => "rhe.jp", "user-agent" => "nya"}, heads)
  end

  def test_server_deny_non_upgrade
    io = StringIO.new
    con = HTTPServerConnection.new(io.method(:write))
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
