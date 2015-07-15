require "test_helper"

class FrameTest < Minitest::Test
  # Frame.parse!
  def test_parse_header_uncomplete
    buffer = "\x00\x00\x00" << "\x00" << "\x00"
    buffer_orig = buffer.dup
    assert_nil(Plum::Frame.parse!(buffer))
    assert_equal(buffer_orig, buffer)
  end

  def test_parse_body_uncomplete
    buffer = "\x00\x00\x03" << "\x00" << "\x00" << "\x00\x00\x00\x00" << "ab"
    buffer_orig = buffer.dup
    assert_nil(Plum::Frame.parse!(buffer))
    assert_equal(buffer_orig, buffer)
  end

  def test_parse
    # R 0x1, stream_id 0x4, body "abc"
    buffer = "\x00\x00\x03" << "\x00" << "\x20" << "\x80\x00\x00\x04" << "abc" << "next_frame_data"
    frame = Plum::Frame.parse!(buffer)
    assert_equal(frame.length, 3)
    assert_equal(frame.type_value, 0x00)
    assert_equal(frame.flags_value, 0x20)
    assert_equal(frame.stream_id, 0x04)
    assert_equal(frame.payload, "abc")
    assert_equal(buffer, "next_frame_data")
  end
end
