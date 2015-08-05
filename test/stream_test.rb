require "test_helper"

using Plum::BinaryString

class StreamTest < Minitest::Test
  include ServerTestUtils

  def test_stream_reserve
    prepare = -> &blk {
      con = open_server_connection
      stream = Stream.new(con, 2)
      blk.call(stream)
    }

    prepare.call {|stream|
      stream.instance_eval { @state = :idle }
      refute_raises {
        stream.reserve
      }
      assert_equal(:reserved_local, stream.state)
    }
    prepare.call {|stream|
      stream.instance_eval { @state = :open }
      assert_connection_error(:protocol_error) {
        stream.reserve
      }
    }
  end

  def test_stream_state_illegal_frame_type
    test = -> (state, &blk) {
      con = open_server_connection
      stream = Stream.new(con, 2)
      stream.instance_eval { @state = state }
      blk.call(stream)
    }

    test.call(:idle) {|stream|
      assert_connection_error(:protocol_error) {
        stream.process_frame(Frame.new(type: :rst_stream, stream_id: stream.id, payload: "\x00\x00\x00\x00"))
      }
      refute_raises {
        stream.process_frame(Frame.new(type: :headers, stream_id: stream.id))
      }
    }
  end

  def test_stream_handle_data
    test = -> (state = :open, &blk) {
      con = open_server_connection
      stream = Stream.new(con, 2)
      stream.instance_eval { @state = state }
      blk.call(stream)
    }

    payload = "ABC" * 5

    test.call {|stream|
      data = nil
      stream.on(:data) {|_data| data = _data }
      stream.process_frame(Frame.new(type: :data, stream_id: stream.id,
                                     flags: [], payload: payload))
      assert_equal(payload, data)
    }

    test.call {|stream|
      data = nil
      stream.on(:data) {|_data| data = _data }
      stream.process_frame(Frame.new(type: :data, stream_id: stream.id,
                                     flags: [:padded], payload: "".push_uint8(6).push(payload).push("\x00"*6)))
      assert_equal(payload, data)
    }

    test.call {|stream|
      assert_connection_error(:protocol_error) {
        stream.process_frame(Frame.new(type: :data, stream_id: stream.id,
                                       flags: [:padded], payload: "".push_uint8(100).push(payload).push("\x00"*6)))
      }
    }

    test.call {|stream|
      stream.process_frame(Frame.new(type: :data, stream_id: stream.id,
                                     flags: [:end_stream], payload: payload))
      assert_equal(:half_closed_remote, stream.state)
    }

    test.call(:half_closed_remote) {|stream|
      stream.process_frame(Frame.new(type: :data, stream_id: stream.id,
                                     flags: [:end_stream], payload: payload))
      last = sent_frames(stream.connection).last
      assert_equal(:rst_stream, last.type)
      assert_equal(StreamError.new(:stream_closed).http2_error_code, last.payload.uint32)
    }
  end

  def test_stream_handle_headers
    test = -> (state = :idle, &blk) {
      con = open_server_connection
      stream = Stream.new(con, 2)
      stream.instance_eval { @state = state }
      blk.call(stream)
    }

    test.call {|stream|
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

    test.call {|stream|
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

    test.call {|stream|
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

    test.call {|stream|
      payload = HPACK::Encoder.new(0).encode([[":path", "/"]])
      assert_connection_error(:protocol_error) {
        stream.process_frame(Frame.new(type: :headers,
                                       stream_id: stream.id,
                                       flags: [:end_headers, :padded],
                                       payload: "".push_uint8(payload.bytesize+1).push(payload).push("\x00"*(payload.bytesize+1))))
      }
    }

    _payload = HPACK::Encoder.new(0).encode([[":path", "/"]])
    test.call(:reserved_local) {|stream|
      assert_connection_error(:protocol_error) {
        stream.process_frame(Frame.new(type: :headers, stream_id: stream.id, flags: [:end_headers, :end_stream], payload: _payload))
      }
    }
    test.call(:closed) {|stream|
      assert_connection_error(:stream_closed) {
        stream.process_frame(Frame.new(type: :headers, stream_id: stream.id, flags: [:end_headers, :end_stream], payload: _payload))
      }
    }
    test.call(:half_closed_remote) {|stream|
      stream.process_frame(Frame.new(type: :headers, stream_id: stream.id, flags: [:end_headers, :end_stream], payload: _payload))
      last = sent_frames(stream.connection).last
      assert_equal(:rst_stream, last.type)
      assert_equal(StreamError.new(:stream_closed).http2_error_code, last.payload.uint32)
    }

    test.call {|stream|
      skip "HEADERS with priority" # TODO
    }
  end

  def test_stream_promise
    con = open_server_connection
    stream = con.__send__(:new_stream, 3)
    push_stream = stream.promise([])
    assert(push_stream.id % 2 == 0)
    assert(push_stream.id > stream.id)
    assert_equal(stream, push_stream.parent)
    assert_includes(stream.children, push_stream)
  end

  def test_stream_window_update
    con = open_server_connection
    stream = Stream.new(con, 1)
    before_ws = stream.recv_remaining_window
    stream.window_update(500)

    last = sent_frames(con).last
    assert_equal(:window_update, last.type)
    assert_equal(500, last.payload.uint32)
    assert_equal(before_ws + 500, stream.recv_remaining_window)
  end

  def test_stream_close
    con = open_server_connection
    stream = Stream.new(con, 1)
    stream.instance_eval { @state = :half_closed_local }
    stream.close(StreamError.new(:frame_size_error).http2_error_code)

    last = sent_frames(con).last
    assert_equal(:rst_stream, last.type)
    assert_equal(StreamError.new(:frame_size_error).http2_error_code, last.payload.uint32)
    assert_equal(:closed, stream.state)
  end
end
