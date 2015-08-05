require "test_helper"

using BinaryString

class StreamHelperTest < Minitest::Test
  def test_stream_window_update
    open_new_stream {|stream|
      before_ws = stream.recv_remaining_window
      stream.window_update(500)

      last = sent_frames.last
      assert_equal(:window_update, last.type)
      assert_equal(500, last.payload.uint32)
      assert_equal(before_ws + 500, stream.recv_remaining_window)
    }
  end

  def test_stream_promise
    open_new_stream {|stream|
      push_stream = stream.promise([])

      assert(push_stream.id % 2 == 0)
      assert(push_stream.id > stream.id)
      assert_equal(stream, push_stream.parent)
      assert_includes(stream.children, push_stream)
    }
  end
end
