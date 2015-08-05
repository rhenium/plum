require "test_helper"

using Plum::BinaryString

class StreamHandleFrameTest < Minitest::Test
  ## DATA
  def test_stream_handle_data
    payload = "ABC" * 5
    open_new_stream(:open) {|stream|
      data = nil
      stream.on(:data) {|_data| data = _data }
      stream.process_frame(Frame.new(type: :data, stream_id: stream.id,
                                     flags: [], payload: payload))
      assert_equal(payload, data)
    }
  end

  def test_stream_handle_data_padded
    payload = "ABC" * 5
    open_new_stream(:open) {|stream|
      data = nil
      stream.on(:data) {|_data| data = _data }
      stream.process_frame(Frame.new(type: :data, stream_id: stream.id,
                                     flags: [:padded], payload: "".push_uint8(6).push(payload).push("\x00"*6)))
      assert_equal(payload, data)
    }
  end

  def test_stream_handle_data_too_long_padding
    payload = "ABC" * 5
    open_new_stream(:open) {|stream|
      assert_connection_error(:protocol_error) {
        stream.process_frame(Frame.new(type: :data, stream_id: stream.id,
                                       flags: [:padded], payload: "".push_uint8(100).push(payload).push("\x00"*6)))
      }
    }
  end

  def test_stream_handle_data_end_stream
    payload = "ABC" * 5
    open_new_stream(:open) {|stream|
      stream.process_frame(Frame.new(type: :data, stream_id: stream.id,
                                     flags: [:end_stream], payload: payload))
      assert_equal(:half_closed_remote, stream.state)
    }
  end

  def test_stream_handle_data_invalid_state
    payload = "ABC" * 5
    open_new_stream(:half_closed_remote) {|stream|
      stream.process_frame(Frame.new(type: :data, stream_id: stream.id,
                                     flags: [:end_stream], payload: payload))
      last = sent_frames.last
      assert_equal(:rst_stream, last.type)
      assert_equal(StreamError.new(:stream_closed).http2_error_code, last.payload.uint32)
    }
  end

  ## HEADERS
  def test_stream_handle_headers_single
    open_new_stream {|stream|
      headers = nil
      stream.on(:headers) {|_headers|
        headers = _headers
      }
      stream.process_frame(Frame.new(type: :headers,
                                     stream_id: stream.id,
                                     flags: [:end_headers],
                                     payload: HPACK::Encoder.new(0).encode([[":path", "/"]])))
      assert_equal(:open, stream.state)
      assert_equal([[":path", "/"]], headers)
    }
  end

  def test_stream_handle_headers_continuation
    open_new_stream {|stream|
      payload = HPACK::Encoder.new(0).encode([[":path", "/"]])
      headers = nil
      stream.on(:headers) {|_headers|
        headers = _headers
      }
      stream.process_frame(Frame.new(type: :headers,
                                     stream_id: stream.id,
                                     flags: [:end_stream],
                                     payload: payload[0..4]))
      assert_equal(nil, headers) # wait CONTINUATION
      stream.process_frame(Frame.new(type: :continuation,
                                     stream_id: stream.id,
                                     flags: [:end_headers],
                                     payload: payload[5..-1]))
      assert_equal(:half_closed_remote, stream.state)
      assert_equal([[":path", "/"]], headers)
    }
  end

  def test_stream_handle_headers_padded
    open_new_stream {|stream|
      payload = HPACK::Encoder.new(0).encode([[":path", "/"]])
      headers = nil
      stream.on(:headers) {|_headers|
        headers = _headers
      }
      stream.process_frame(Frame.new(type: :headers,
                                     stream_id: stream.id,
                                     flags: [:end_headers, :padded],
                                     payload: "".push_uint8(payload.bytesize).push(payload).push("\x00"*payload.bytesize)))
      assert_equal([[":path", "/"]], headers)
    }
  end

  def test_stream_handle_headers_too_long_padding
    open_new_stream {|stream|
      payload = HPACK::Encoder.new(0).encode([[":path", "/"]])
      assert_connection_error(:protocol_error) {
        stream.process_frame(Frame.new(type: :headers,
                                       stream_id: stream.id,
                                       flags: [:end_headers, :padded],
                                       payload: "".push_uint8(payload.bytesize+1).push(payload).push("\x00"*(payload.bytesize+1))))
      }
    }
  end

  def test_stream_handle_headers_broken
    open_new_stream {|stream|
      payload = "\x00\x01\x02"
      assert_connection_error(:compression_error) {
        stream.process_frame(Frame.new(type: :headers,
                                       stream_id: stream.id,
                                       flags: [:end_headers],
                                       payload: payload))
      }
    }
  end

  def test_stream_handle_headers_state
    _payload = HPACK::Encoder.new(0).encode([[":path", "/"]])
    open_new_stream(:reserved_local) {|stream|
      assert_connection_error(:protocol_error) {
        stream.process_frame(Frame.new(type: :headers, stream_id: stream.id, flags: [:end_headers, :end_stream], payload: _payload))
      }
    }
    open_new_stream(:closed) {|stream|
      assert_connection_error(:stream_closed) {
        stream.process_frame(Frame.new(type: :headers, stream_id: stream.id, flags: [:end_headers, :end_stream], payload: _payload))
      }
    }
    open_new_stream(:half_closed_remote) {|stream|
      stream.process_frame(Frame.new(type: :headers, stream_id: stream.id, flags: [:end_headers, :end_stream], payload: _payload))
      last = sent_frames.last
      assert_equal(:rst_stream, last.type)
      assert_equal(StreamError.new(:stream_closed).http2_error_code, last.payload.uint32)
    }
  end

  def test_stream_handle_headers_priority
    open_server_connection {|con|
      parent = open_new_stream(con)
      stream = open_new_stream(con)

      headers = nil
      stream.on(:headers) {|_headers| headers = _headers }
      header_block = HPACK::Encoder.new(0).encode([[":path", "/"]])
      payload = "".push_uint32((1 << 31) | parent.id)
                  .push_uint8(50)
                  .push(header_block)
      stream.process_frame(Frame.new(type: :headers,
                                     stream_id: stream.id,
                                     flags: [:end_headers, :priority],
                                     payload: payload))
      assert_equal(true, stream.exclusive)
      assert_equal(parent, stream.parent)
      assert_equal(50, stream.weight)
      assert_equal([[":path", "/"]], headers)
    }
  end

  ## PRIORITY
  def test_stream_handle_priority
    open_server_connection {|con|
      parent = open_new_stream(con)
      stream = open_new_stream(con)

      payload = "".push_uint32((1 << 31) | parent.id)
                  .push_uint8(50)
      stream.process_frame(Frame.new(type: :priority,
                                     stream_id: stream.id,
                                     payload: payload))
      assert_equal(true, stream.exclusive)
      assert_equal(parent, stream.parent)
      assert_equal(50, stream.weight)
    }
  end
end
