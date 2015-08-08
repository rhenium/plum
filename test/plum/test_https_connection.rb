require "test_helper"

using Plum::BinaryString

class HTTPSConnectionNegotiationTest < Minitest::Test
  def test_server_must_raise_cprotocol_error_invalid_magic_short
    con = HTTPSConnection.new(StringIO.new)
    assert_connection_error(:protocol_error) {
      con << "HELLO"
    }
  end

  def test_server_must_raise_cprotocol_error_invalid_magic_long
    con = HTTPSConnection.new(StringIO.new)
    assert_connection_error(:protocol_error) {
      con << ("HELLO" * 100) # over 24
    }
  end

  def test_server_must_raise_cprotocol_error_non_settings_after_magic
    con = HTTPSConnection.new(StringIO.new)
    con << Connection::CLIENT_CONNECTION_PREFACE
    assert_connection_error(:protocol_error) {
      con << Frame.new(type: :window_update, stream_id: 0, payload: "".push_uint32(1)).assemble
    }
  end

  def test_server_accept_fragmented_magic
    magic = Connection::CLIENT_CONNECTION_PREFACE
    con = HTTPSConnection.new(StringIO.new)
    assert_no_error {
      con << magic[0...5]
      con << magic[5..-1]
      con << Frame.new(type: :settings, stream_id: 0).assemble
    }
  end
end
