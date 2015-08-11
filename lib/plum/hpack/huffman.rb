using Plum::BinaryString

module Plum
  module HPACK
    module Huffman
      extend self

      # Static-Huffman-encodes the specified String.
      def encode(bytestr)
        ret = []
        remain = 0
        bytestr.each_byte do |b|
          val, len = HUFFMAN_TABLE[b]
          l = len - remain

          ret[-1] |= val >> l if ret.size > 0
          while l > 0
            ret << ((val >> (l - 8)) & 0xff)
            l -= 8
          end
          remain = -l % 8
        end
        ret[-1] |= (1 << remain) - 1 if remain > 0
        ret.pack("C*")
      end

      # Static-Huffman-decodes the specified String.
      def decode(encoded)
        bits = encoded.unpack("B*")[0]
        buf = ""
        outl = []
        while (n = bits.byteshift(1)).bytesize > 0
          if c = HUFFMAN_DECODE_TABLE[buf << n]
            buf = ""
            outl << c
          end
        end

        if buf.bytesize > 7
          raise HPACKError.new("huffman: padding is too large (> 7 bits)")
        elsif buf != "1" * buf.bytesize
          raise HPACKError.new("huffman: unknown suffix: #{buf}")
        else
          outl.pack("C*")
        end
      end
    end
  end
end
