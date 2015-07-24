module Plum
  module BinaryString
    refine String do
      def uint8(pos = 0)
        byteslice(pos, 1).unpack("C")[0]
      end

      def uint16(pos = 0)
        byteslice(pos, 2).unpack("n")[0]
      end

      def uint24(pos = 0)
        (uint16(pos) << 8) | uint8(pos + 2)
      end

      def uint32(pos = 0)
        byteslice(pos, 4).unpack("N")[0]
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

      alias push <<

      def shift(count)
        enc = self.encoding
        force_encoding(Encoding::BINARY)
        out = slice!(0, count)
        force_encoding(enc)
        out
      end
    end
  end
end
