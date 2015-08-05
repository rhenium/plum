require "test_helper"

using Plum::BinaryString
class ServerConnectionFlowControlTest < Minitest::Test
  def test_server_dont_send_data_exceeding_csend_window
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

  def test_server_dont_send_data_upto_updated_csend_window
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
end
