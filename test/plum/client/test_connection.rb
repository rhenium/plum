require "test_helper"

using Plum::BinaryString
class ClientConnectionTest < Minitest::Test
  def test_open_stream
    con = open_client_connection
    stream = con.open_stream
    assert(stream.id % 2 == 1, "Stream ID is not odd")
    assert_equal(:idle, stream.state)
  end
end
