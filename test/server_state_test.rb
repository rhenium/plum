require "test_helper"

using Plum::BinaryString

class ServerStateTest < Minitest::Test
  def test_server_must_repond_cprotocol_error_on_invalid_magic
    invalid_magic = "HELLO"
    start_server do |plum|
      start_client do |sock|
        sock.write(invalid_magic)
        frame =  nil
        loop do
          ret = sock.readpartial(1024)
          frame = Plum::Frame.parse!(ret)
          break if frame.type != :settings # server connection preface
        end
        assert_equal(:goaway, frame.type) # connection error
        assert_equal(0x01, frame.payload.uint32(4)) # protocol error
      end
    end
  end
end
