# -*- frozen-string-literal: true -*-
using Plum::BinaryString

module Plum
  module HPACK
    module Huffman
      extend self

      # Static-Huffman-encodes the specified String.
      def encode(bytestr)
        out = String.new
        bytestr.each_byte do |b|
          out << HUFFMAN_TABLE[b]
        end
        out << "1" * ((8 - out.bytesize) % 8)
        [out].pack("B*")
      end

      # Static-Huffman-decodes the specified String.
      def decode(encoded)
        bits = encoded.unpack("B*")[0]
        out = []
        buf = String.new
        bits.each_char do |cb|
          buf << cb
          if c = HUFFMAN_TABLE_INVERSED[buf]
            raise HPACKError.new("huffman: EOS detected") if c == 256
            out << c
            buf.clear
          end
        end

        if buf.bytesize > 7
          raise HPACKError.new("huffman: padding is too large (> 7 bits)")
        elsif buf != "1" * buf.bytesize
          raise HPACKError.new("huffman: unknown suffix: #{buf}")
        else
          out.pack("C*")
        end
      end
    end
  end
end
