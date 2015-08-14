require "test_helper"

using Plum::BinaryString

class StreamHandleFrameTest < Minitest::Test
  ## DATA
  def test_stream_handle_data
    payload = "ABC" * 5
    open_new_stream(state: :open) {|stream|
      data = nil
      stream.on(:data) {|_data| data = _data }
      stream.receive_frame(Frame.new(type: :data, stream_id: stream.id,
                                     flags: [], payload: payload))
      assert_equal(payload, data)
    }
  end

  def test_stream_handle_data_padded
    payload = "ABC" * 5
    open_new_stream(state: :open) {|stream|
      data = nil
      stream.on(:data) {|_data| data = _data }
      stream.receive_frame(Frame.new(type: :data, stream_id: stream.id,
                                     flags: [:padded], payload: "".push_uint8(6).push(payload).push("\x00"*6)))
      assert_equal(payload, data)
    }
  end

  def test_stream_handle_data_too_long_padding
    payload = "ABC" * 5
    open_new_stream(state: :open) {|stream|
      assert_connection_error(:protocol_error) {
        stream.receive_frame(Frame.new(type: :data, stream_id: stream.id,
                                       flags: [:padded], payload: "".push_uint8(100).push(payload).push("\x00"*6)))
      }
    }
  end

  def test_stream_handle_data_end_stream
    payload = "ABC" * 5
    open_new_stream(state: :open) {|stream|
      stream.receive_frame(Frame.new(type: :data, stream_id: stream.id,
                                     flags: [:end_stream], payload: payload))
      assert_equal(:half_closed_remote, stream.state)
    }
  end

  def test_stream_handle_data_invalid_state
    payload = "ABC" * 5
    open_new_stream(state: :half_closed_remote) {|stream|
      assert_stream_error(:stream_closed) {
        stream.receive_frame(Frame.new(type: :data, stream_id: stream.id,
                                       flags: [:end_stream], payload: payload))
      }
    }
  end

  ## HEADERS
  def test_stream_handle_headers_single
    open_new_stream {|stream|
      headers = nil
      stream.on(:headers) {|_headers|
        headers = _headers
      }
      stream.receive_frame(Frame.new(type: :headers,
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
      stream.receive_frame(Frame.new(type: :headers,
                                     stream_id: stream.id,
                                     flags: [:end_stream],
                                     payload: payload[0..4]))
      assert_equal(nil, headers) # wait CONTINUATION
      stream.receive_frame(Frame.new(type: :continuation,
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
      stream.receive_frame(Frame.new(type: :headers,
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
        stream.receive_frame(Frame.new(type: :headers,
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
        stream.receive_frame(Frame.new(type: :headers,
                                       stream_id: stream.id,
                                       flags: [:end_headers],
                                       payload: payload))
      }
    }
  end

  def test_stream_handle_headers_state
    _payload = HPACK::Encoder.new(0).encode([[":path", "/"]])
    open_new_stream(state: :reserved_local) {|stream|
      assert_connection_error(:protocol_error) {
        stream.receive_frame(Frame.new(type: :headers, stream_id: stream.id, flags: [:end_headers, :end_stream], payload: _payload))
      }
    }
    open_new_stream(state: :closed) {|stream|
      assert_connection_error(:stream_closed) {
        stream.receive_frame(Frame.new(type: :headers, stream_id: stream.id, flags: [:end_headers, :end_stream], payload: _payload))
      }
    }
    open_new_stream(state: :half_closed_remote) {|stream|
      assert_stream_error(:stream_closed) {
        stream.receive_frame(Frame.new(type: :headers, stream_id: stream.id, flags: [:end_headers, :end_stream], payload: _payload))
      }
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
      stream.receive_frame(Frame.new(type: :headers,
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
      stream.receive_frame(Frame.new(type: :priority,
                                     stream_id: stream.id,
                                     payload: payload))
      assert_equal(true, stream.exclusive)
      assert_equal(parent, stream.parent)
      assert_equal(50, stream.weight)
    }
  end

  def test_stream_handle_priority_self_depend
    open_server_connection {|con|
      stream = open_new_stream(con)
      payload = "".push_uint32((1 << 31) | stream.id).push_uint8(6)
      stream.receive_frame(Frame.new(type: :priority,
                                     stream_id: stream.id,
                                     payload: payload))
      last = sent_frames.last
      assert_equal(:rst_stream, last.type)
      assert_equal(HTTPError::ERROR_CODES[:protocol_error], last.payload.uint32)
    }
  end

  def test_stream_handle_priority_exclusive
    open_server_connection {|con|
      parent = open_new_stream(con)
      stream0 = open_new_stream(con, parent: parent)
      stream1 = open_new_stream(con, parent: parent)
      stream2 = open_new_stream(con, parent: parent)

      payload = "".push_uint32((1 << 31) | parent.id).push_uint8(6)
      stream0.receive_frame(Frame.new(type: :priority,
                                      stream_id: stream0.id,
                                      payload: payload))
      assert_equal(parent, stream0.parent)
      assert_equal(stream0, stream1.parent)
      assert_equal(stream0, stream2.parent)
    }
  end

  def test_stream_handle_frame_size_error
    open_new_stream {|stream|
      assert_stream_error(:frame_size_error) {
        stream.receive_frame(Frame.new(type: :priority,
                                       stream_id: stream.id,
                                       payload: "\x00"))
      }
    }
  end

  ## RST_STREAM
  def test_stream_handle_rst_stream
    open_new_stream(state: :reserved_local) {|stream|
      stream.receive_frame(Frame.new(type: :rst_stream,
                                     stream_id: stream.id,
                                     payload: "\x00\x00\x00\x00"))
      assert_equal(:closed, stream.state)
    }
  end

  def test_stream_handle_rst_stream_idle
    open_new_stream(state: :idle) {|stream|
      assert_connection_error(:protocol_error) {
        stream.receive_frame(Frame.new(type: :rst_stream,
                                       stream_id: stream.id,
                                       payload: "\x00\x00\x00\x00"))
      }
    }
  end

  def test_stream_handle_rst_stream_frame_size
    open_new_stream(state: :reserved_local) {|stream|
      assert_connection_error(:frame_size_error) {
        stream.receive_frame(Frame.new(type: :rst_stream,
                                       stream_id: stream.id,
                                       payload: "\x00\x00\x00"))
      }
    }
  end

end
