require "test_helper"

using Plum::BinaryString

class ServerConnectionHandleFrameTest < Minitest::Test
  ## SETTINGS
  def test_server_handle_settings
    open_server_connection {|con|
      assert_equal(4096, con.remote_settings[:header_table_size])
      con << Frame.new(type: :settings, stream_id: 0, payload: "\x00\x01\x00\x00\x10\x10").assemble
      assert_equal(0x1010, con.remote_settings[:header_table_size])
    }
  end

  def test_server_handle_settings
    open_server_connection {|con|
      assert_no_error {
        con << Frame.new(type: :settings, stream_id: 0, flags: [:ack], payload: "").assemble
      }
      assert_connection_error(:frame_size_error) {
        con << Frame.new(type: :settings, stream_id: 0, flags: [:ack], payload: "\x00").assemble
      }
    }
  end

  def test_server_handle_settings_invalid
    open_server_connection {|con|
      assert_no_error {
        con << Frame.new(type: :settings, stream_id: 0, payload: "\xff\x01\x00\x00\x10\x10").assemble
      }
    }
  end

  ## PING
  def test_server_handle_ping
    open_server_connection {|con|
      con << Frame.new(type: :ping, flags: [], stream_id: 0, payload: "AAAAAAAA").assemble
      last = sent_frames.last
      assert_equal(:ping, last.type)
      assert_equal([:ack], last.flags)
      assert_equal("AAAAAAAA", last.payload)
    }
  end

  def test_server_handle_ping_error
    open_server_connection {|con|
      assert_connection_error(:frame_size_error) {
        con << Frame.new(type: :ping, stream_id: 0, payload: "A" * 7).assemble
      }
    }
  end

  def test_server_handle_ping_ack
    open_server_connection {|con|
      con << Frame.new(type: :ping, flags: [:ack], stream_id: 0, payload: "A" * 8).assemble
      last = sent_frames.last
      refute_equal(:ping, last.type) if last
    }
  end

  ## GOAWAY
  def test_server_handle_goaway_reply
    open_server_connection {|con|
      assert_no_error {
        con << Frame.goaway(1234, :stream_closed).assemble
      }
      assert_equal(:goaway, sent_frames.last.type)
    }
  end
end
