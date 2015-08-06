require "test_helper"

using BinaryString

class ServerConnectionHelperTest < Minitest::Test
  def test_server_window_update
    open_server_connection {|con|
      before_ws = con.recv_remaining_window
      con.window_update(500)

      last = sent_frames.last
      assert_equal(:window_update, last.type)
      assert_equal(500, last.payload.uint32)
      assert_equal(before_ws + 500, con.recv_remaining_window)
    }
  end

end
