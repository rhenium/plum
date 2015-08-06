require "test_helper"

using Plum::BinaryString

class ServerConnectionTest < Minitest::Test
  def test_server_must_raise_cframe_size_error_when_exeeeded_max_size
    _settings = "".push_uint16(Frame::SETTINGS_TYPE[:max_frame_size]).push_uint32(2**14)
    con = open_server_connection
    con.settings(max_frame_size: 2**14)
    refute_raises {
      con << Frame.new(type: :settings, stream_id: 0, payload: _settings*(2**14/6)).assemble
    }
    assert_connection_error(:frame_size_error) {
      con << Frame.new(type: :settings, stream_id: 0, payload: _settings*((2**14)/6+1)).assemble
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
      refute_raises {
        con << Frame.new(type_value: 0x0f, stream_id: 0).assemble
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
      con << Frame.new(type: :continuation, flags: [:end_headers], stream_id: 3, payload: "hello").assemble
      assert_equal(:open, con.state)
    }
  end
end
