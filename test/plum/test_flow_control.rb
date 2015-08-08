require "test_helper"

using BinaryString

class FlowControlTest < Minitest::Test
  def test_flow_control_window_update_server
    open_server_connection {|con|
      before_ws = con.recv_remaining_window
      con.window_update(500)

      last = sent_frames.last
      assert_equal(:window_update, last.type)
      assert_equal(0, last.stream_id)
      assert_equal(500, last.payload.uint32)
      assert_equal(before_ws + 500, con.recv_remaining_window)
    }
  end

  def test_flow_control_window_update_stream
    open_new_stream {|stream|
      before_ws = stream.recv_remaining_window
      stream.window_update(500)

      last = sent_frames.last
      assert_equal(:window_update, last.type)
      assert_equal(stream.id, last.stream_id)
      assert_equal(500, last.payload.uint32)
      assert_equal(before_ws + 500, stream.recv_remaining_window)
    }
  end

  def test_flow_control_window_update_zero
    open_new_stream {|stream|
      con = stream.connection
      # stream error
      con << Frame.new(type: :window_update,
                       stream_id: stream.id,
                       payload: "".push_uint32(0)).assemble
      last = sent_frames.last
      assert_equal(:rst_stream, last.type)
      assert_equal(ERROR_CODES[:protocol_error], last.payload.uint32)
    }
  end

  def test_flow_control_dont_send_data_exceeding_send_window
    open_new_stream {|stream|
      con = stream.connection
      con << Frame.new(type: :settings,
                       stream_id: 0,
                       payload: "".push_uint16(Frame::SETTINGS_TYPE[:initial_window_size])
                                  .push_uint32(4*2+1)).assemble
      # only extend stream window size
      con << Frame.new(type: :window_update,
                       stream_id: stream.id,
                       payload: "".push_uint32(100)).assemble
      10.times {|i|
        stream.send Frame.new(type: :data,
                              stream_id: stream.id,
                              payload: "".push_uint32(i))
      }

      last = sent_frames.last
      assert_equal(1, last.payload.uint32)
    }
  end

  def test_flow_control_dont_send_data_upto_updated_send_window
    open_new_stream {|stream|
      con = stream.connection
      con << Frame.new(type: :settings,
                       stream_id: 0,
                       payload: "".push_uint16(Frame::SETTINGS_TYPE[:initial_window_size])
                                  .push_uint32(4*2+1)).assemble
      10.times {|i|
        stream.send Frame.new(type: :data,
                              stream_id: stream.id,
                              payload: "".push_uint32(i))
      }
      # only extend stream window size
      con << Frame.new(type: :window_update,
                       stream_id: stream.id,
                       payload: "".push_uint32(100)).assemble
      # and extend connection window size
      con << Frame.new(type: :window_update,
                       stream_id: 0,
                       payload: "".push_uint32(4*2+1)).assemble

      last = sent_frames.last
      assert_equal(3, last.payload.uint32)
    }
  end

  def test_flow_control_update_initial_window_size
    open_new_stream {|stream|
      con = stream.connection
      con << Frame.new(type: :settings,
                       stream_id: 0,
                       payload: "".push_uint16(Frame::SETTINGS_TYPE[:initial_window_size])
                                  .push_uint32(4*2+1)).assemble
      10.times {|i|
        stream.send Frame.new(type: :data,
                              stream_id: stream.id,
                              payload: "".push_uint32(i))
      }
      # only extend stream window size
      con << Frame.new(type: :window_update,
                       stream_id: stream.id,
                       payload: "".push_uint32(100)).assemble
      # and update initial window size
      con << Frame.new(type: :settings,
                       stream_id: 0,
                       payload: "".push_uint16(Frame::SETTINGS_TYPE[:initial_window_size])
                                  .push_uint32(4*4+1)).assemble

      last = sent_frames.reverse.find {|f| f.type == :data }
      assert_equal(3, last.payload.uint32)
    }
  end
end