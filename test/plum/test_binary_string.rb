require "test_helper"

using BinaryString

class BinaryStringTest < Minitest::Test
  def test_uint8
    assert_equal(0x67, "\x67".uint8)
    assert_equal(0x75, "\x67\x75".uint8(1))
  end

  def test_uint16
    assert_equal(0x78ff, "\x78\xff".uint16)
    assert_equal(0xee55, "\x78\xee\x55".uint16(1))
  end

  def test_uint24
    assert_equal(0x005554, "\x00\x55\x54".uint24)
    assert_equal(0x005554, "\x2f\xaa\x00\x55\x54".uint24(2))
  end

  def test_uint32
    assert_equal(0x00555400, "\x00\x55\x54\x00".uint32)
    assert_equal(0x00555400, "\x2f\xaa\x00\x55\x54\x00".uint32(2))
  end

  def test_push_uint8
    assert_equal("\x24", "".push_uint8(0x24))
  end

  def test_push_uint16
    assert_equal("\x24\x11", "".push_uint16(0x2411))
  end

  def test_push_uint24
    assert_equal("\x11\x11\x24", "".push_uint24(0x111124))
  end

  def test_push_uint32
    assert_equal("\x10\x00\x00\x24", "".push_uint32(0x10000024))
  end

  def test_push
    assert_equal("adh", "ad".push("h"))
  end

  def test_byteshift
    sushi = "\u{1f363}".encode(Encoding::UTF_8)
    assert_equal("\xf0".b, sushi.byteshift(1).b)
    assert_equal("\x9f\x8d\xa3".b, sushi.b)
  end

  def test_each_byteslice_block
    ret = []
    string = "12345678"
    string.each_byteslice(3) {|part| ret << part }
    assert_equal(["123", "456", "78"], ret)
  end

  def test_each_byteslice_enume
    string = "12345678"
    ret = string.each_byteslice(3)
    assert_equal(["123", "456", "78"], ret.to_a)
  end

  def test_chunk
    string = "12345678"
    ret = string.chunk(3)
    assert_equal(["123", "456", "78"], ret)
  end
end
