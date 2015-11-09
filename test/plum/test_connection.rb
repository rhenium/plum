require "test_helper"

using Plum::BinaryString

class ConnectionTest < Minitest::Test
  def test_server_must_raise_frame_size_error_when_exeeeded_max_size
    _settings = "".push_uint16(Frame::SETTINGS_TYPE[:max_frame_size]).push_uint32(2**14)
    limit = 2 ** 14

    new_con = -> (&blk) {
      c = open_server_connection
      c.settings(max_frame_size: limit)
      blk.call c
    }

    new_con.call {|con|
      assert_no_error {
        con << Frame.new(type: :settings, stream_id: 0, payload: _settings * (limit / 6)).assemble
      }
    }
    new_con.call {|con|
      assert_connection_error(:frame_size_error) {
        con << Frame.new(type: :settings, stream_id: 0, payload: _settings * (limit / 6 + 1)).assemble
      }
    }
    new_con.call {|con|
      assert_connection_error(:frame_size_error) {
        con << Frame.new(type: :headers, stream_id: 3, payload: "\x00" * (limit + 1)).assemble
      }
    }
    new_con.call {|con|
      assert_stream_error(:frame_size_error) {
        con << Frame.new(type: :headers, stream_id: 3, flags: [:end_headers], payload: "").assemble
        con << Frame.new(type: :data, stream_id: 3, payload: "\x00" * (limit + 1)).assemble
      }
    }
  end

  def test_server_raise_cprotocol_error_illegal_control_stream
    [:data, :headers, :priority, :rst_stream, :push_promise, :continuation].each do |type|
      con = open_server_connection
      assert_connection_error(:protocol_error) {
        con << Frame.new(type: type, stream_id: 0).assemble
      }
    end
  end

  def test_server_ignore_unknown_frame_type
    open_server_connection {|con|
      assert_no_error {
        con << "\x00\x00\x00\x0f\x00\x00\x00\x00\x00" # type: 0x0f, no flags, no payload, stream 0
      }
    }
  end

  def test_server_raise_cprotocol_error_client_start_even_stream_id
    con = open_server_connection
    assert_connection_error(:protocol_error) {
      con << Frame.new(type: :headers, flags: [:end_headers], stream_id: 2).assemble
    }
  end

  def test_server_raise_cprotocol_error_client_start_small_stream_id
    con = open_server_connection
    con << Frame.new(type: :headers, flags: [:end_headers], stream_id: 51).assemble
    assert_connection_error(:protocol_error) {
      con << Frame.new(type: :headers, flags: [:end_headers], stream_id: 31).assemble
    }
  end

  def test_server_raise_cprotocol_error_invalid_continuation_state
    prepare = -> &blk {
      con = open_server_connection
      con << Frame.new(type: :headers, flags: [:end_headers], stream_id: 1).assemble
      con << Frame.new(type: :headers, flags: [:end_stream], stream_id: 3).assemble
      blk.call(con)
    }

    prepare.call {|con|
      assert_connection_error(:protocol_error) {
        con << Frame.new(type: :data, stream_id: 1, payload: "hello").assemble
      }
    }
    prepare.call {|con|
      assert_connection_error(:protocol_error) {
        con << Frame.new(type: :data, stream_id: 3, payload: "hello").assemble
      }
    }
    prepare.call {|con|
      assert_equal(:waiting_continuation, con.state)
      con << Frame.new(type: :continuation, flags: [:end_headers], stream_id: 3, payload: "").assemble
      assert_equal(:open, con.state)
    }
  end

  def test_connection_local_error
    open_server_connection { |con|
      assert_raises(LocalConnectionError) {
        con << Frame.goaway(0, :frame_size_error).assemble
      }
    }
  end
end
