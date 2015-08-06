require "test_helper"

using BinaryString

class StreamHelperTest < Minitest::Test
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
