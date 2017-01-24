require_relative "../../utils"

using BinaryString
class ServerConnectionHandleFrameTest < Test::Unit::TestCase
  ## SETTINGS
  def test_server_handle_settings
    open_server_connection { |con|
      assert_equal(4096, con.remote_settings[:header_table_size])
      con << Frame.craft(type: :settings, stream_id: 0, payload: "\x00\x01\x00\x00\x10\x10").assemble
      assert_equal(0x1010, con.remote_settings[:header_table_size])
    }
  end

  def test_server_handle_settings_ack
    open_server_connection { |con|
      assert_no_error {
        con << Frame.craft(type: :settings, stream_id: 0, flags: [:ack], payload: "").assemble
      }
      assert_connection_error(:frame_size_error) {
        con << Frame.craft(type: :settings, stream_id: 0, flags: [:ack], payload: "\x00").assemble
      }
    }
  end

  def test_server_handle_settings_invalid
    open_server_connection { |con|
      assert_no_error {
        con << Frame.craft(type: :settings, stream_id: 0, payload: "\xff\x01\x00\x00\x10\x10").assemble
      }
    }
  end

  ## PING
  def test_server_handle_ping
    open_server_connection { |con|
      con << Frame.craft(type: :ping, flags: [], stream_id: 0, payload: "AAAAAAAA").assemble
      last = sent_frames.last
      assert_equal(:ping, last.type)
      assert_equal([:ack], last.flags)
      assert_equal("AAAAAAAA", last.payload)
    }
  end

  def test_server_handle_ping_error
    open_server_connection { |con|
      assert_connection_error(:frame_size_error) {
        con << Frame.craft(type: :ping, stream_id: 0, payload: "A" * 7).assemble
      }
    }
  end

  def test_server_handle_ping_ack
    open_server_connection { |con|
      con << Frame.craft(type: :ping, flags: [:ack], stream_id: 0, payload: "A" * 8).assemble
      last = sent_frames.last
      refute_equal(:ping, last.type) if last
    }
  end

  ## GOAWAY
  def test_server_handle_goaway_reply
    open_server_connection { |con|
      assert_no_error {
        begin
          con << Frame::Goaway.new(1, :stream_closed).assemble
        rescue LocalHTTPError
        end
      }
      assert_equal(:goaway, sent_frames.last.type)
    }
  end
end
