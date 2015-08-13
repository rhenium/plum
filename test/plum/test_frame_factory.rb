require "test_helper"

using Plum::BinaryString
class FrameFactoryTest < Minitest::Test
  def test_rst_stream
    frame = Frame.rst_stream(123, :stream_closed)
    assert_frame(frame,
                 type: :rst_stream,
                 stream_id: 123)
    assert_equal(HTTPError::ERROR_CODES[:stream_closed], frame.payload.uint32)
  end

  def test_goaway
    frame = Frame.goaway(0x55, :stream_closed, "debug")
    assert_frame(frame,
                 type: :goaway,
                 stream_id: 0,
                 payload: "\x00\x00\x00\x55\x00\x00\x00\x05debug")
  end

  def test_settings
    frame = Frame.settings(header_table_size: 0x1010)
    assert_frame(frame,
                 type: :settings,
                 stream_id: 0,
                 flags: [],
                 payload: "\x00\x01\x00\x00\x10\x10")
  end

  def test_settings_ack
    frame = Frame.settings(:ack)
    assert_frame(frame,
                 type: :settings,
                 stream_id: 0,
                 flags: [:ack],
                 payload: "")
  end

  def test_ping
    frame = Frame.ping("12345678")
    assert_frame(frame,
                 type: :ping,
                 stream_id: 0,
                 flags: [],
                 payload: "12345678")
  end

  def test_ping_ack
    frame = Frame.ping(:ack, "12345678")
    assert_frame(frame,
                 type: :ping,
                 stream_id: 0,
                 flags: [:ack],
                 payload: "12345678")
  end
end
