require "test_helper"

class FrameUtilsTest < Minitest::Test
  def test_frame_enough_short
    frame = Frame::Data.new(1, "123")
    ret = frame.to_enum(:split, 3).to_a
    assert_equal(1, ret.size)
    assert_equal("123", ret.first.payload)
  end

  def test_frame_data
    frame = Frame::Data.new(1, "12345", end_stream: true)
    ret = frame.to_enum(:split, 2).to_a
    assert_equal(3, ret.size)
    assert_equal("12", ret.first.payload)
    assert_equal([], ret.first.flags)
    assert_equal("5", ret.last.payload)
    assert_equal([:end_stream], ret.last.flags)
  end

  def test_headers_split
    frame = Frame.craft(type: :headers, flags: [:priority, :end_stream, :end_headers], stream_id: 1, payload: "1234567")
    ret = frame.to_enum(:split, 3).to_a
    assert_equal(3, ret.size)
    assert_equal("123", ret[0].payload)
    assert_equal([:end_stream, :priority], ret[0].flags)
    assert_equal("456", ret[1].payload)
    assert_equal([], ret[1].flags)
    assert_equal("7", ret[2].payload)
    assert_equal([:end_headers], ret[2].flags)
  end

  def test_push_promise_split
    frame = Frame::PushPromise.new(1, 2, "1234567", end_headers: true)
    ret = frame.to_enum(:split, 3).to_a
    assert_equal(4, ret.size)
    assert_equal("\x00\x00\x00", ret[0].payload)
    assert_equal([], ret[0].flags)
    assert_equal("\x0212", ret[1].payload)
    assert_equal([], ret[1].flags)
    assert_equal("345", ret[2].payload)
    assert_equal([], ret[2].flags)
    assert_equal("67", ret[3].payload)
    assert_equal([:end_headers], ret[3].flags)
  end

  def test_frame_parse_settings
    # :header_table_size => 0x1010, :enable_push => 0x00, :header_table_size => 0x1011 (overwrite)
    frame = Frame.parse!("\x00\x00\x12\x04\x00\x00\x00\x00\x00" "\x00\x01\x00\x00\x10\x10\x00\x02\x00\x00\x00\x00\x00\x01\x00\x00\x10\x11")
    ret = frame.parse_settings
    assert_equal(0x1011, ret[:header_table_size])
    assert_equal(0x0000, ret[:enable_push])
  end
end
