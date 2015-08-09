require "test_helper"

using BinaryString

class ServerConnectionUtilsTest < Minitest::Test
  def test_server_ping
    open_server_connection {|con|
      con.ping("ABCABCAB")

      last = sent_frames.last
      assert_equal(:ping, last.type)
      assert_equal([], last.flags)
      assert_equal("ABCABCAB", last.payload)
    }
  end

  def test_server_goaway
    open_server_connection {|con|
      con << Frame.headers(3, "", :end_stream, :end_headers).assemble
      con.goaway(:stream_closed)

      last = sent_frames.last
      assert_equal(:goaway, last.type)
      assert_equal([], last.flags)
      assert_equal(3, last.payload.uint32)
      assert_equal(ERROR_CODES[:stream_closed], last.payload.uint32(4))
    }
  end
end
