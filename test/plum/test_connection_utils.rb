require_relative "../utils"

using Plum::BinaryString

class ServerConnectionUtilsTest < Test::Unit::TestCase
  def test_server_ping
    open_server_connection { |con|
      con.ping("ABCABCAB")

      last = sent_frames.last
      assert_equal(:ping, last.type)
      assert_equal([], last.flags)
      assert_equal("ABCABCAB", last.payload)
    }
  end

  def test_server_goaway
    open_server_connection { |con|
      con << Frame::Headers.new(3, "", end_stream: true, end_headers: true).assemble
      con.goaway(:stream_closed)

      last = sent_frames.last
      assert_equal(:goaway, last.type)
      assert_equal([], last.flags)
      assert_equal(3, last.payload.uint32)
      assert_equal(HTTPError::ERROR_CODES[:stream_closed], last.payload.uint32(4))
    }
  end

  def test_push_enabled
    open_server_connection { |con|
      con << Frame::Settings.new(enable_push: 0).assemble
      assert_equal(false, con.push_enabled?)
      con << Frame::Settings.new(enable_push: 1).assemble
      assert_equal(true, con.push_enabled?)
    }
  end
end
