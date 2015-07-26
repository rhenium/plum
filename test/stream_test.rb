require "test_helper"

include Plum
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
end
