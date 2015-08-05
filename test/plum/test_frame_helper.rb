require "test_helper"

class FrameHelperTest < Minitest::Test
  def test_frame_enough_short
    frame = Frame.new(type: :data, stream_id: 1, payload: "123")
    ret = frame.split_data(3)
    assert_equal(1, ret.size)
    assert_equal("123", ret.first.payload)
  end

  def test_frame_unknown
    frame = Frame.new(type: :settings, stream_id: 1, payload: "123")
    assert_raises { frame.split_data(2) }
    assert_raises { frame.split_headers(2) }
  end

  def test_frame_data
    frame = Frame.new(type: :data, flags: [:end_stream], stream_id: 1, payload: "12345")
    ret = frame.split_data(3)
    assert_equal(2, ret.size)
    assert_equal("123", ret.first.payload)
    assert_equal([], ret.first.flags)
    assert_equal("45", ret.last.payload)
    assert_equal([:end_stream], ret.last.flags)
  end

  def test_frame_headers
    frame = Frame.new(type: :headers, flags: [:priority, :end_stream, :end_headers], stream_id: 1, payload: "1234567")
    ret = frame.split_headers(3)
    assert_equal(3, ret.size)
    assert_equal("123", ret[0].payload)
    assert_equal([:priority, :end_stream].sort, ret[0].flags.sort)
    assert_equal("456", ret[1].payload)
    assert_equal([], ret[1].flags)
    assert_equal("7", ret[2].payload)
    assert_equal([:end_headers], ret[2].flags)
  end
end
