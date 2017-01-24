require_relative "../../utils"

class HPACKEncoderTest < Test::Unit::TestCase
  # C.1.1
  def test_hpack_encode_integer_small
    result = new_encoder(1 << 31).__send__(:encode_integer, 10, 5, 0b00000000)
    assert_equal([0b00001010].pack("C*"), result)
  end

  # C.1.2
  def test_hpack_encode_integer_big
    result = new_encoder(1 << 31).__send__(:encode_integer, 1337, 5, 0b000000)
    assert_equal([0b00011111, 0b10011010, 0b00001010].pack("C*"), result)
  end

  # C.1.3
  def test_hpack_encode_integer_8prefix
    result = new_encoder(1 << 31).__send__(:encode_integer, 42, 8, 0b000000)
    assert_equal([0b00101010].pack("C*"), result)
  end

  def test_hpack_encode_single
    headers = [["custom-key", "custom-header"]]
    encoded = new_encoder(1 << 31).encode(headers)
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
    encoded = new_encoder(1 << 31).encode(headers)
    decoded = new_decoder.decode(encoded)
    assert_equal(headers, decoded)
  end

  def test_hpack_encode_without_indexing
    encoder = new_encoder(1 << 31, indexing: false)
    headers1 = [["custom-key", "custom-header"]]
    encoder.encode(headers1)
    assert_equal([], encoder.dynamic_table)
    headers2 = [[":method", "custom-header"]]
    encoder.encode(headers2)
    assert_equal([], encoder.dynamic_table)
  end

  def test_hpack_encode_without_huffman
    encoder = new_encoder(1 << 31, huffman: false)
    headers = [["custom-key", "custom-header"]]
    ret = encoder.encode(headers)
    assert_equal("\x40\x0acustom-key\x0dcustom-header", ret)
  end

  private
  def new_decoder(settings_header_table_size = 1 << 31)
    Plum::HPACK::Decoder.new(settings_header_table_size)
  end

  def new_encoder(*args)
    Plum::HPACK::Encoder.new(*args)
  end
end
