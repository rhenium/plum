require "test_helper"

using Plum::BinaryString
class DecodersTest < Minitest::Test
  def test_base_decode
    decoder = Decoders::Base.new
    assert_equal("abc", decoder.decode("abc"))
  end
  
  def test_base_finish
    decoder = Decoders::Base.new
    decoder.finish
  end

  def test_deflate_decode
    decoder = Decoders::Deflate.new
    assert_equal("hello", decoder.decode("\x78\x9c\xcb\x48\xcd\xc9\xc9\x07\x00\x06\x2c\x02\x15"))
  end

  def test_deflate_decode_error
    decoder = Decoders::Deflate.new
    assert_raises(DecoderError) {
      decoder.decode("\x79\x9c\xcb\x48\xcd\xc9\xc9\x07\x00\x06\x2c\x02\x15")
    }
  end

  def test_deflate_finish_error
    decoder = Decoders::Deflate.new
    decoder.decode("\x78\x9c\xcb\x48\xcd\xc9\xc9\x07\x00\x06\x2c\x02")
    assert_raises(DecoderError) {
      decoder.finish
    }
  end

  def test_gzip_decode
    decoder = Decoders::GZip.new
    assert_equal("hello", decoder.decode("\x1f\x8b\x08\x00\x1a\x96\xe0\x4c\x00\x03\xcb\x48\xcd\xc9\xc9\x07\x00\x86\xa6\x10\x36\x05\x00\x00\x00"))
  end

  def test_gzip_decode_error
    decoder = Decoders::GZip.new
    assert_raises(DecoderError) {
      decoder.decode("\x2f\x8b\x08\x00\x1a\x96\xe0\x4c\x00\x03\xcb\x48\xcd\xc9\xc9\x07\x00\x86\xa6\x10\x36\x05\x00\x00\x00")
    }
  end

  def test_gzip_finish_error
    decoder = Decoders::GZip.new
    decoder.decode("\x1f\x8b\x08\x00\x1a\x96")
    assert_raises(DecoderError) {
      decoder.finish
    }
  end
end
