module Plum
  class BinaryString < String
    def initialize(*args)
      super
      force_encoding(Encoding::BINARY)
    end

    def uint8(pos = 0)
      slice(pos, 1).unpack("C")[0]
    end

    def uint16(pos = 0)
      slice(pos, 2).unpack("n")[0]
    end

    def uint24(pos = 0)
      (slice(pos, 2).uint16 << 8) | slice(pos + 2, 1).uint8
    end

    def uint32(pos = 0)
      slice(pos, 4).unpack("N")[0]
    end

    def uint8!
      shift(1).unpack("C")[0]
    end

    def uint16!
      shift(2).unpack("n")[0]
    end

    def uint24!
      (uint16! << 8) | uint8!
    end

    def uint32!
      shift(4).unpack("N")[0]
    end

    def push_uint8(val)
      self << [val].pack("C")
    end

    def push_uint16(val)
      self << [val].pack("n")
    end

    def push_uint24(val)
      push_uint16(val >> 8)
      push_uint8(val & ((1 << 8) - 1))
    end

    def push_uint32(val)
      self << [val].pack("N")
    end

    def dup
      BinaryString.new(super)
    end

    alias push <<

    def shift(count)
      slice!(0, count)
    end

    def slice(*args)
      BinaryString.new(super(*args))
    end
    alias [] slice

    def slice!(*args)
      BinaryString.new(super(*args))
    end

    def inspect
      each_byte.inject("\"") {|s, b| s << "\\x%02X" % b } << "\""
    end
  end
end
