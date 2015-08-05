require "test_helper"

using Plum::BinaryString

class ServerConnectionTest < Minitest::Test
  include ServerTestUtils

  def test_server_must_raise_cprotocol_error_invalid_magic_short
    con = ServerConnection.new(nil)
    assert_connection_error(:protocol_error) {
      con << "HELLO"
    }
  end

  def test_server_must_raise_cprotocol_error_invalid_magic_long
    con = ServerConnection.new(nil)
    assert_connection_error(:protocol_error) {
      con << ("HELLO" * 100) # over 24
    }
  end

  def test_server_must_raise_cprotocol_error_non_settings_after_magic
    con = ServerConnection.new(nil)
    con << ServerConnection::CLIENT_CONNECTION_PREFACE
    assert_connection_error(:protocol_error) {
      con << Frame.new(type: :window_update, stream_id: 0, payload: "".push_uint32(1)).assemble
    }
  end

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

  def test_server_accept_fragmented_magic
    io = StringIO.new
    magic = ServerConnection::CLIENT_CONNECTION_PREFACE
    con = ServerConnection.new(io)
    con << magic[0...5]
    con << magic[5..-1]
    con << Frame.new(type: :settings, stream_id: 0).assemble
  end

  def test_server_accept_client_preface_and_return_ack
    io = StringIO.new
    con = ServerConnection.new(io)
    con << ServerConnection::CLIENT_CONNECTION_PREFACE
    con << Frame.new(type: :settings, stream_id: 0).assemble
    assert_equal(:open, con.state)

    last = sent_frames(con).last
    assert_equal(:settings, last.type)
    assert_includes(last.flags, :ack)
  end

  def test_server_accept_settings
    open_server_connection {|con|
      assert_equal(4096, con.remote_settings[:header_table_size])
      con << Frame.new(type: :settings, stream_id: 0, payload: "\x00\x01\x00\x00\x10\x10").assemble
      assert_equal(0x1010, con.remote_settings[:header_table_size])
    }
    open_server_connection {|con|
      refute_raises {
        con << Frame.new(type: :settings, stream_id: 0, payload: "\xff\x01\x00\x00\x10\x10").assemble
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

  def test_server_ping
    prepare = -> &blk {
      con = open_server_connection
      con << Frame.new(type: :headers, flags: [:end_headers], stream_id: 1).assemble
      blk.call(con)
    }

    prepare.call {|con|
      con << Frame.new(type: :ping, flags: [], stream_id: 0, payload: "AAAAAAAA").assemble
      last = sent_frames.last
      assert_equal(:ping, last.type)
      assert_equal([:ack], last.flags)
      assert_equal("AAAAAAAA", last.payload)
    }
    prepare.call {|con|
      assert_connection_error(:frame_size_error) {
        con << Frame.new(type: :ping, stream_id: 0, payload: "A" * 7).assemble
      }
    }
    prepare.call {|con|
      con << Frame.new(type: :ping, flags: [:ack], stream_id: 0, payload: "A" * 8).assemble
      last = sent_frames.last
      refute_equal(:ping, last.type) if last
    }
  end
end
