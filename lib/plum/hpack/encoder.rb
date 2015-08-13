using Plum::BinaryString

module Plum
  module HPACK
    class Encoder
      include HPACK::Context

      def initialize(dynamic_table_limit)
        super
      end

      # currently only support 0x0000XXXX type (without indexing)
      # and not huffman
      # +---+---+---+---+---+---+---+---+
      # | 0 | 0 | 0 | 0 |       0       |
      # +---+---+-----------------------+
      # | H |     Name Length (7+)      |
      # +---+---------------------------+
      # |  Name String (Length octets)  |
      # +---+---------------------------+
      # | H |     Value Length (7+)     |
      # +---+---------------------------+
      # | Value String (Length octets)  |
      # +-------------------------------+
      def encode(headers)
        out = ""
        headers.each do |name, value|
          out << "\x00"
          out << encode_string(name.to_s)
          out << encode_string(value.to_s)
        end
        out
      end

      private
      def encode_integer(value, prefix_length)
        mask = (1 << prefix_length) - 1
        out = ""

        if value < mask
          out.push_uint8(value)
        else
          value -= mask
          out.push_uint8(mask)
          while value >= mask
            out.push_uint8((value % 0b10000000) + 0b10000000)
            value >>= 7
          end
          out.push_uint8(value)
        end
      end

      def encode_string(str)
        huffman_str = Huffman.encode(str)
        if huffman_str.bytesize < str.bytesize
          lenstr = encode_integer(huffman_str.bytesize, 7).force_encoding(Encoding::BINARY)
          lenstr.setbyte(0, lenstr.uint8(0) | 0b10000000)
          lenstr << huffman_str
        else
          encode_integer(str.bytesize, 7) << str
        end
      end
    end
  end
end
