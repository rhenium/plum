require "test_helper"

class HPACKHuffmanTest < Minitest::Test
  def test_hpack_huffman_encode
    text = "\x10\x60\x2a\x1d\x94\x47\x82\x2c\x3d\x19\xbf\x8e\xd9\x24\xba\xe6\xb4\x1a\xe1\x5c\x39\x0f\x61\xf4\x3b\x08\x62\x54\x15\x0c"
    expected = "\xff\xff\xfe\xdf\xff\xbf\x3f\xff\xff\xf3\xff\xff\xdd\x8b\xff\xf9\xfe\xa0\xff\xff\xff\x5f\xff\xfe\x3f\xff\xfd\x7f\xff\xe5\xff\xcf\xff\xfc\x7f\xff\xe8\xff\xff\xdb\xff\xff\xfe\xdf\xff\xfe\x7f\xff\xc1\xff\xff\xff\xec\x1f\xff\xff\xe7\xfb\xff\xff\xfe\x88\xf7\xff\xff\xff\x97\xff\xff\xf5\x7f"
    assert_equal(expected.force_encoding(Encoding::BINARY), Plum::HPACK::Huffman.encode(text).force_encoding(Encoding::BINARY))
  end

  def test_hpack_huffman_decode
    encoded = "\xff\xff\xfe\xdf\xff\xbf\x3f\xff\xff\xf3\xff\xff\xdd\x8b\xff\xf9\xfe\xa0\xff\xff\xff\x5f\xff\xfe\x3f\xff\xfd\x7f\xff\xe5\xff\xcf\xff\xfc\x7f\xff\xe8\xff\xff\xdb\xff\xff\xfe\xdf\xff\xfe\x7f\xff\xc1\xff\xff\xff\xec\x1f\xff\xff\xe7\xfb\xff\xff\xfe\x88\xf7\xff\xff\xff\x97\xff\xff\xf5\x7f"
    expected = "\x10\x60\x2a\x1d\x94\x47\x82\x2c\x3d\x19\xbf\x8e\xd9\x24\xba\xe6\xb4\x1a\xe1\x5c\x39\x0f\x61\xf4\x3b\x08\x62\x54\x15\x0c"
    assert_equal(expected.force_encoding(Encoding::BINARY), Plum::HPACK::Huffman.decode(encoded).force_encoding(Encoding::BINARY))
  end

  def test_too_long_padding
    encoded = "\x1c\x64\xff\xff\xff"
    assert_raises(Plum::HPACKError) {
      Plum::HPACK::Huffman.decode(encoded)
    }
  end

  def test_padding_not_filled
    encoded = "\x1c\x71\xfe"
    assert_raises(Plum::HPACKError) {
      Plum::HPACK::Huffman.decode(encoded)
    }
  end

  def test_eos_in_encoded
    encoded = "\xff\xff\xff\xff" # \xff\xff\xff\xfc + padding
    assert_raises(Plum::HPACKError) {
      Plum::HPACK::Huffman.decode(encoded)
    }
  end
end
