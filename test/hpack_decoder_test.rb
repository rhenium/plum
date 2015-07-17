require "test_helper"

class HPACKDecoderTest < Minitest::Test
  # C.1.1
  def test_hpack_read_integer_small
    buf = [0b11001010, 0b00001111].pack("C*").b
    result = new_decoder.__send__(:read_integer!, buf, 5)
    assert_equal(10, result)
    assert_equal([0b00001111].pack("C*").b, buf)
  end

  # C.1.2
  def test_hpack_read_integer_big
    buf = [0b11011111, 0b10011010, 0b00001010, 0b00001111].pack("C*").b
    result = new_decoder.__send__(:read_integer!, buf, 5)
    assert_equal(1337, result)
    assert_equal([0b00001111].pack("C*").b, buf)
  end

  # C.1.3
  def test_hpack_read_integer_8prefix
    buf = [0b00101010, 0b00001111].pack("C*").b
    result = new_decoder.__send__(:read_integer!, buf, 8)
    assert_equal(42, result)
    assert_equal([0b00001111].pack("C*").b, buf)
  end

  # C.2.1
  def test_hpack_decode_indexing
    encoded = "\x40\x0a\x63\x75\x73\x74\x6f\x6d\x2d\x6b\x65\x79\x0d\x63\x75\x73\x74\x6f\x6d\x2d\x68\x65\x61\x64\x65\x72".b
    result = new_decoder.decode(encoded)
    assert_equal([["custom-key", "custom-header"]], result)
  end

  # C.2.2
  def test_hpack_decode_without_indexing
    encoded = "\x04\x0c\x2f\x73\x61\x6d\x70\x6c\x65\x2f\x70\x61\x74\x68".b
    result = new_decoder.decode(encoded)
    assert_equal([[":path", "/sample/path"]], result)
  end

  # C.2.3
  def test_hpack_decode_without_indexing2
    encoded = "\x10\x08\x70\x61\x73\x73\x77\x6f\x72\x64\x06\x73\x65\x63\x72\x65\x74".b
    result = new_decoder.decode(encoded)
    assert_equal([["password", "secret"]], result)
  end

  # C.2.4
  def test_hpack_decode_index
    encoded = "\x82".b
    result = new_decoder.decode(encoded)
    assert_equal([[":method", "GET"]], result)
  end

  # C.3.1
  def test_hpack_decode_headers_without_huffman
    decoder = new_decoder
    encoded = "\x82\x86\x84\x41\x0f\x77\x77\x77\x2e\x65\x78\x61\x6d\x70\x6c\x65\x2e\x63\x6f\x6d".b
    result = decoder.decode(encoded)
    expected = [
      [":method", "GET"],
      [":scheme", "http"],
      [":path", "/"],
      [":authority", "www.example.com"]
    ]
    assert_equal(expected, result)

    decoder # for C.3.2
  end

  # C.3.2
  def test_hpack_decode_headers_without_huffman2
    decoder = test_hpack_decode_headers_without_huffman
    encoded = "\x82\x86\x84\xbe\x58\x08\x6e\x6f\x2d\x63\x61\x63\x68\x65".b
    result = decoder.decode(encoded)
    expected = [
      [":method", "GET"],
      [":scheme", "http"],
      [":path", "/"],
      [":authority", "www.example.com"],
      ["cache-control", "no-cache"],
    ]
    assert_equal(expected, result)

    decoder # for C.3.3
  end

  # C.3.3
  def test_hpack_decode_headers_without_huffman3
    decoder = test_hpack_decode_headers_without_huffman2
    encoded = "\x82\x87\x85\xbf\x40\x0a\x63\x75\x73\x74\x6f\x6d\x2d\x6b\x65\x79\x0c\x63\x75\x73\x74\x6f\x6d\x2d\x76\x61\x6c\x75\x65".b
    result = decoder.decode(encoded)
    expected = [
      [":method", "GET"],
      [":scheme", "https"],
      [":path", "/index.html"],
      [":authority", "www.example.com"],
      ["custom-key", "custom-value"],
    ]
    assert_equal(expected, result)
  end

  # C.4.1
  def test_hpack_decode_headers_with_huffman
    decoder = new_decoder
    encoded = "\x82\x86\x84\x41\x8c\xf1\xe3\xc2\xe5\xf2\x3a\x6b\xa0\xab\x90\xf4\xff".b
    result = decoder.decode(encoded)
    expected = [
      [":method", "GET"],
      [":scheme", "http"],
      [":path", "/"],
      [":authority", "www.example.com"]
    ]
    assert_equal(expected, result)

    decoder # for C.4.2
  end

  # C.4.2
  def test_hpack_decode_headers_with_huffman2
    decoder = test_hpack_decode_headers_with_huffman
    encoded = "\x82\x86\x84\xbe\x58\x86\xa8\xeb\x10\x64\x9c\xbf".b
    result = decoder.decode(encoded)
    expected = [
      [":method", "GET"],
      [":scheme", "http"],
      [":path", "/"],
      [":authority", "www.example.com"],
      ["cache-control", "no-cache"],
    ]
    assert_equal(expected, result)

    decoder # for C.4.3
  end

  # C.4.3
  def test_hpack_decode_headers_with_huffman3
    decoder = test_hpack_decode_headers_with_huffman2
    encoded = "\x82\x87\x85\xbf\x40\x88\x25\xa8\x49\xe9\x5b\xa9\x7d\x7f\x89\x25\xa8\x49\xe9\x5b\xb8\xe8\xb4\xbf".b
    result = decoder.decode(encoded)
    expected = [
      [":method", "GET"],
      [":scheme", "https"],
      [":path", "/index.html"],
      [":authority", "www.example.com"],
      ["custom-key", "custom-value"],
    ]
    assert_equal(expected, result)
  end

  # C.5.1
  def test_hpack_decode_response_without_huffman
    decoder = new_decoder(256)
    encoded = "\x48\x03\x33\x30\x32\x58\x07\x70\x72\x69\x76\x61\x74\x65\x61\x1d\x4d\x6f\x6e\x2c\x20\x32\x31\x20\x4f\x63\x74\x20\x32\x30\x31\x33\x20\x32\x30\x3a\x31\x33\x3a\x32\x31\x20\x47\x4d\x54\x6e\x17\x68\x74\x74\x70\x73\x3a\x2f\x2f\x77\x77\x77\x2e\x65\x78\x61\x6d\x70\x6c\x65\x2e\x63\x6f\x6d".b
    result = decoder.decode(encoded)
    expected = [
      [":status", "302"],
      ["cache-control", "private"],
      ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
      ["location", "https://www.example.com"]
    ]
    assert_equal(expected, result)

    decoder # for C.5.2
  end

  # C.5.2
  def test_hpack_decode_response_without_huffman2
    decoder = test_hpack_decode_response_without_huffman
    encoded = "\x48\x03\x33\x30\x37\xc1\xc0\xbf".b
    result = decoder.decode(encoded)
    expected = [
      [":status", "307"],
      ["cache-control", "private"],
      ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
      ["location", "https://www.example.com"]
    ]
    assert_equal(expected, result)
    refute_includes(decoder.dynamic_table, [":status", "302"]) # evicted

    decoder # for C.5.3
  end

  # C.5.3
  def test_hpack_decode_response_without_huffman3
    decoder = test_hpack_decode_response_without_huffman2
    encoded = "\x88\xc1\x61\x1d\x4d\x6f\x6e\x2c\x20\x32\x31\x20\x4f\x63\x74\x20\x32\x30\x31\x33\x20\x32\x30\x3a\x31\x33\x3a\x32\x32\x20\x47\x4d\x54\xc0\x5a\x04\x67\x7a\x69\x70\x77\x38\x66\x6f\x6f\x3d\x41\x53\x44\x4a\x4b\x48\x51\x4b\x42\x5a\x58\x4f\x51\x57\x45\x4f\x50\x49\x55\x41\x58\x51\x57\x45\x4f\x49\x55\x3b\x20\x6d\x61\x78\x2d\x61\x67\x65\x3d\x33\x36\x30\x30\x3b\x20\x76\x65\x72\x73\x69\x6f\x6e\x3d\x31".b
    result = decoder.decode(encoded)
    expected = [
      [":status", "200"],
      ["cache-control", "private"],
      ["date", "Mon, 21 Oct 2013 20:13:22 GMT"],
      ["location", "https://www.example.com"],
      ["content-encoding", "gzip"],
      ["set-cookie", "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"]
    ]
    assert_equal(expected, result)
  end

  # C.6.1
  def test_hpack_decode_response_with_huffman
    decoder = new_decoder(256)
    encoded = "\x48\x82\x64\x02\x58\x85\xae\xc3\x77\x1a\x4b\x61\x96\xd0\x7a\xbe\x94\x10\x54\xd4\x44\xa8\x20\x05\x95\x04\x0b\x81\x66\xe0\x82\xa6\x2d\x1b\xff\x6e\x91\x9d\x29\xad\x17\x18\x63\xc7\x8f\x0b\x97\xc8\xe9\xae\x82\xae\x43\xd3".b
    result = decoder.decode(encoded)
    expected = [
      [":status", "302"],
      ["cache-control", "private"],
      ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
      ["location", "https://www.example.com"]
    ]
    assert_equal(expected, result)

    decoder # for C.6.2
  end

  # C.6.2
  def test_hpack_decode_response_with_huffman2
    decoder = test_hpack_decode_response_with_huffman
    encoded = "\x48\x83\x64\x0e\xff\xc1\xc0\xbf".b
    result = decoder.decode(encoded)
    expected = [
      [":status", "307"],
      ["cache-control", "private"],
      ["date", "Mon, 21 Oct 2013 20:13:21 GMT"],
      ["location", "https://www.example.com"]
    ]
    assert_equal(expected, result)
    refute_includes(decoder.dynamic_table, [":status", "302"]) # evicted

    decoder # for C.6.3
  end

  # C.6.3
  def test_hpack_decode_response_with_huffman3
    decoder = test_hpack_decode_response_with_huffman2
    encoded = "\x88\xc1\x61\x96\xd0\x7a\xbe\x94\x10\x54\xd4\x44\xa8\x20\x05\x95\x04\x0b\x81\x66\xe0\x84\xa6\x2d\x1b\xff\xc0\x5a\x83\x9b\xd9\xab\x77\xad\x94\xe7\x82\x1d\xd7\xf2\xe6\xc7\xb3\x35\xdf\xdf\xcd\x5b\x39\x60\xd5\xaf\x27\x08\x7f\x36\x72\xc1\xab\x27\x0f\xb5\x29\x1f\x95\x87\x31\x60\x65\xc0\x03\xed\x4e\xe5\xb1\x06\x3d\x50\x07".b
    result = decoder.decode(encoded)
    expected = [
      [":status", "200"],
      ["cache-control", "private"],
      ["date", "Mon, 21 Oct 2013 20:13:22 GMT"],
      ["location", "https://www.example.com"],
      ["content-encoding", "gzip"],
      ["set-cookie", "foo=ASDJKHQKBZXOQWEOPIUAXQWEOIU; max-age=3600; version=1"]
    ]
    assert_equal(expected, result)
  end

  private
  def new_decoder(settings_header_table_size = 1 << 31)
    Plum::HPACK::Decoder.new(settings_header_table_size)
  end
end
