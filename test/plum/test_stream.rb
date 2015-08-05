require "test_helper"

using Plum::BinaryString

class StreamTest < Minitest::Test
  def test_stream_state_illegal_frame_type
    open_new_stream {|stream|
      assert_connection_error(:protocol_error) {
        stream.process_frame(Frame.new(type: :rst_stream, stream_id: stream.id, payload: "\x00\x00\x00\x00"))
      }
    }
  end

  def test_stream_close
    open_new_stream(:half_closed_local) {|stream|
      stream.close(StreamError.new(:frame_size_error).http2_error_code)

      last = sent_frames.last
      assert_equal(:rst_stream, last.type)
      assert_equal(StreamError.new(:frame_size_error).http2_error_code, last.payload.uint32)
      assert_equal(:closed, stream.state)
    }
  end
end
