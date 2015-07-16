module Plum
  module HPACK
    module Huffman
      extend self

      # TODO: performance
      def encode(bytestr)
        out = ""
        bytestr.bytes.each do |b|
          out << HUFFMAN_TABLE[b]
        end
        out << "1" * (8 - (out.size % 8))
        [out].pack("B*").b
      end

      # TODO: performance
      def decode(encoded)
        bits = encoded.unpack("B*")[0]
        buf = ""
        outl = []
        while (n = bits.slice!(0, 1)).size > 0
          if c = HUFFMAN_DECODE_TABLE[buf << n]
            buf = ""
            outl << c
          end
        end

        if buf.size > 7
          raise HPACKError.new("huffman: padding is too large (> 7 bits)")
        elsif buf != "1" * buf.size
          raise HPACKError.new("huffman: unknown suffix: #{buf}")
        else
          outl.pack("C*").b
        end
      end
    end
  end
end
