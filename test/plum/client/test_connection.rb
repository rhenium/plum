require "test_helper"

using Plum::BinaryString
class ClientConnectionTest < Minitest::Test
  def test_open_stream
    con = open_client_connection
    stream = con.open_stream(weight: 256)
    assert(stream.id % 2 == 1)
    assert_equal(256, stream.weight)
  end
end
