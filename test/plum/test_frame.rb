require "test_helper"

class FrameTest < Minitest::Test
  # Frame.parse!
  def test_parse_header_uncomplete
    buffer = "\x00\x00\x00" << "\x00" << "\x00"
    buffer.force_encoding(Encoding::BINARY)
    buffer_orig = buffer.dup
    assert_nil(Plum::Frame.parse!(buffer))
    assert_equal(buffer_orig, buffer)
  end

  def test_parse_body_uncomplete
    buffer = "\x00\x00\x03" << "\x00" << "\x00" << "\x00\x00\x00\x00" << "ab"
    buffer.force_encoding(Encoding::BINARY)
    buffer_orig = buffer.dup
    assert_nil(Plum::Frame.parse!(buffer))
    assert_equal(buffer_orig, buffer)
  end

  def test_parse
    # R 0x1, stream_id 0x4, body "abc"
    buffer = "\x00\x00\x03" << "\x00" << "\x09" << "\x00\x00\x00\x04" << "abc" << "next_frame_data"
    buffer.force_encoding(Encoding::BINARY)
    frame = Plum::Frame.parse!(buffer)
    assert_equal(3, frame.length)
    assert_equal(:data, frame.type)
    assert_equal([:end_stream, :padded], frame.flags)
    assert_equal(0x04, frame.stream_id)
    assert_equal("abc", frame.payload)
    assert_equal("next_frame_data", buffer)
    assert_equal(true, frame.frozen?)
  end

  # Frame#assemble
  def test_assemble
    frame = Plum::Frame.craft(type: :push_promise, flags: [:end_headers, :padded], stream_id: 0x678, payload: "payl")
    bin = "\x00\x00\x04" << "\x05" << "\x0c" << "\x00\x00\x06\x78" << "payl"
    assert_equal(bin, frame.assemble)
  end

  # Frame.craft
  def test_new_raw
    frame = Plum::Frame.craft(type: :data,
                              stream_id: 12345,
                              flags: [:end_stream, :padded],
                              payload: "ぺいろーど".encode(Encoding::UTF_8))
    assert_equal("ぺいろーど", frame.payload)
    assert_equal("ぺいろーど".bytesize, frame.length)
    assert_equal(:data, frame.type) # DATA
    assert_equal([:end_stream, :padded], frame.flags) # 0x01 | 0x08
    assert_equal(12345, frame.stream_id)
  end

  def test_inspect
    frame = Plum::Frame.craft(type: :data,
                              stream_id: 12345,
                              flags: [:end_stream, :padded],
                              payload: "ぺいろーど")
    frame.inspect
  end
end
