require_relative "../utils"

using BinaryString
class FrameFactoryTest < Test::Unit::TestCase
  def test_rst_stream
    frame = Frame::RstStream.new(123, :stream_closed)
    assert_frame(frame,
                 type: :rst_stream,
                 stream_id: 123)
    assert_equal(HTTPError::ERROR_CODES[:stream_closed], frame.payload.uint32)
  end

  def test_goaway
    frame = Frame::Goaway.new(0x55, :stream_closed, "debug")
    assert_frame(frame,
                 type: :goaway,
                 stream_id: 0,
                 payload: "\x00\x00\x00\x55\x00\x00\x00\x05debug")
  end

  def test_settings
    frame = Frame::Settings.new(header_table_size: 0x1010)
    assert_frame(frame,
                 type: :settings,
                 stream_id: 0,
                 flags: [],
                 payload: "\x00\x01\x00\x00\x10\x10")
  end

  def test_settings_ack
    frame = Frame::Settings.ack
    assert_frame(frame,
                 type: :settings,
                 stream_id: 0,
                 flags: [:ack],
                 payload: "")
  end

  def test_ping
    frame = Frame::Ping.new("12345678")
    assert_frame(frame,
                 type: :ping,
                 stream_id: 0,
                 flags: [],
                 payload: "12345678")
  end

  def test_ping_ack
    frame = Frame::Ping.new(:ack, "12345678")
    assert_frame(frame,
                 type: :ping,
                 stream_id: 0,
                 flags: [:ack],
                 payload: "12345678")
  end

  def test_continuation
    frame = Frame::Continuation.new(123, "abc", end_headers: true)
    assert_frame(frame,
                 type: :continuation,
                 stream_id: 123,
                 flags: [:end_headers],
                 payload: "abc")
  end

  def test_data
    frame = Frame::Data.new(123, "abc".force_encoding("UTF-8"))
    assert_frame(frame,
                 type: :data,
                 stream_id: 123,
                 flags: [],
                 payload: "abc")
    assert_equal(Encoding::BINARY, frame.payload.encoding)
  end

  def test_headers
    frame = Frame::Headers.new(123, "abc", end_stream: true)
    assert_frame(frame,
                 type: :headers,
                 stream_id: 123,
                 flags: [:end_stream],
                 payload: "abc")
  end

  def test_push_promise
    frame = Frame::PushPromise.new(345, 2, "abc", end_headers: true)
    assert_frame(frame,
                 type: :push_promise,
                 stream_id: 345,
                 flags: [:end_headers],
                 payload: "\x00\x00\x00\x02abc")
  end
end
