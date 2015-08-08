require "test_helper"

using BinaryString

class ServerConnectionHelperTest < Minitest::Test
  def test_server_ping
    open_server_connection {|con|
      con.ping("ABCABCAB")

      last = sent_frames.last
      assert_equal(:ping, last.type)
      assert_equal([], last.flags)
      assert_equal("ABCABCAB", last.payload)
    }
  end
end
