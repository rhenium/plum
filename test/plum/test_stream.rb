require "test_helper"

using Plum::BinaryString

class StreamTest < Minitest::Test
  def test_stream_illegal_frame_type
    open_new_stream { |stream|
      assert_connection_error(:protocol_error) {
        stream.receive_frame(Frame::Goaway.new(0, :no_error))
      }
    }
  end

  def test_stream_unknown_frame_type
    open_new_stream { |stream|
      assert_no_error {
        stream.receive_frame(Frame::Unknown.new(0x0f, flags_value: 0, stream_id: stream.id, payload: "\x00\x00\x00\x00"))
      }
    }
  end

  def test_stream_remote_error
    open_server_connection { |con|
      stream = nil
      con.on(:headers) { |s|
        stream = s
        raise RemoteStreamError.new(:frame_size_error)
      }

      assert_stream_error(:frame_size_error) {
        con << Frame::Headers.new(1, "", end_headers: true).assemble
      }

      last = sent_frames.last
      assert_equal(:rst_stream, last.type)
      assert_equal(HTTPError::ERROR_CODES[:frame_size_error], last.payload.uint32)
      assert_equal(:closed, stream.state)
    }
  end

  def test_stream_local_error
    open_server_connection { |con|
      stream = type = nil
      con.on(:rst_stream) { |s, t| stream = s; type = t }

      con << Frame::Headers.new(1, "", end_headers: true).assemble
      con << Frame::RstStream.new(1, :frame_size_error).assemble

      assert_equal(1, stream.id)
      assert_equal(:frame_size_error, type)
    }
  end
end
