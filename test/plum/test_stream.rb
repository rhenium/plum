require "test_helper"

using Plum::BinaryString

class StreamTest < Minitest::Test
  def test_stream_reserve
    open_new_stream {|stream|
      stream.reserve
      assert_equal(:reserved_local, stream.state)
    }
    open_new_stream(:open) {|stream|
      assert_connection_error(:protocol_error) {
        stream.reserve
      }
    }
  end

  def test_stream_state_illegal_frame_type
    open_new_stream {|stream|
      assert_connection_error(:protocol_error) {
        stream.process_frame(Frame.new(type: :rst_stream, stream_id: stream.id, payload: "\x00\x00\x00\x00"))
      }
    }
  end

  def test_stream_handle_data
    payload = "ABC" * 5

    open_new_stream(:open) {|stream|
      data = nil
      stream.on(:data) {|_data| data = _data }
      stream.process_frame(Frame.new(type: :data, stream_id: stream.id,
                                     flags: [], payload: payload))
      assert_equal(payload, data)
    }

    open_new_stream(:open) {|stream|
      data = nil
      stream.on(:data) {|_data| data = _data }
      stream.process_frame(Frame.new(type: :data, stream_id: stream.id,
                                     flags: [:padded], payload: "".push_uint8(6).push(payload).push("\x00"*6)))
      assert_equal(payload, data)
    }

    open_new_stream(:open) {|stream|
      assert_connection_error(:protocol_error) {
        stream.process_frame(Frame.new(type: :data, stream_id: stream.id,
                                       flags: [:padded], payload: "".push_uint8(100).push(payload).push("\x00"*6)))
      }
    }

    open_new_stream(:open) {|stream|
      stream.process_frame(Frame.new(type: :data, stream_id: stream.id,
                                     flags: [:end_stream], payload: payload))
      assert_equal(:half_closed_remote, stream.state)
    }

    open_new_stream(:half_closed_remote) {|stream|
      stream.process_frame(Frame.new(type: :data, stream_id: stream.id,
                                     flags: [:end_stream], payload: payload))
      last = sent_frames.last
      assert_equal(:rst_stream, last.type)
      assert_equal(StreamError.new(:stream_closed).http2_error_code, last.payload.uint32)
    }
  end

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
    open_new_stream {|stream|
      skip "HEADERS with priority" # TODO
    }
  end

  def test_stream_promise
    open_new_stream {|stream|
      push_stream = stream.promise([])

      assert(push_stream.id % 2 == 0)
      assert(push_stream.id > stream.id)
      assert_equal(stream, push_stream.parent)
      assert_includes(stream.children, push_stream)
    }
  end

  def test_stream_window_update
    open_new_stream {|stream|
      before_ws = stream.recv_remaining_window
      stream.window_update(500)

      last = sent_frames.last
      assert_equal(:window_update, last.type)
      assert_equal(500, last.payload.uint32)
      assert_equal(before_ws + 500, stream.recv_remaining_window)
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
