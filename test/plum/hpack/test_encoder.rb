require "test_helper"

class HPACKEncoderTest < Minitest::Test
  # C.1.1
  def test_hpack_encode_integer_small
    result = new_encoder.__send__(:encode_integer, 10, 5)
    assert_equal([0b00001010].pack("C*"), result)
  end

  # C.1.2
  def test_hpack_encode_integer_big
    result = new_encoder.__send__(:encode_integer, 1337, 5)
    assert_equal([0b00011111, 0b10011010, 0b00001010].pack("C*"), result)
  end

  # C.1.3
  def test_hpack_encode_integer_8prefix
    result = new_encoder.__send__(:encode_integer, 42, 8)
    assert_equal([0b00101010].pack("C*"), result)
  end

  def test_hpack_encode_single
    headers = [["custom-key", "custom-header"]]
    encoded = new_encoder.encode(headers)
    decoded = new_decoder.decode(encoded)
    assert_equal(headers, decoded)
  end

  def test_hpack_encode_multiple
    headers = [
      [":method", "GET"],
      [":scheme", "http"],
      [":path", "/"],
      [":authority", "www.example.com"]
    ]
    encoded = new_encoder.encode(headers)
    decoded = new_decoder.decode(encoded)
    assert_equal(headers, decoded)
  end

  private
  def new_decoder(settings_header_table_size = 1 << 31)
    Plum::HPACK::Decoder.new(settings_header_table_size)
  end

  def new_encoder(settings_header_table_size = 1 << 31)
    Plum::HPACK::Encoder.new(settings_header_table_size)
  end
end
