using Plum::BinaryString

module Plum
  module HPACK
    class Encoder
      include HPACK::Context

      def initialize(dynamic_table_limit)
        super
      end

      def encode(headers)
        out = ""
        headers.each do |name, value|
          name = name.to_s; value = value.to_s
          if index = search(name, value)
            out << encode_indexed(index)
          elsif index = search(name, nil)
            out << encode_half_indexed(index, value, true) # incremental indexing
          else
            out << encode_literal(name, value, true) # incremental indexing
          end
        end
        out.force_encoding(Encoding::BINARY)
      end

      private
      # +---+---+---+---+---+---+---+---+
      # | 0 | 1 |           0           |
      # +---+---+-----------------------+
      # | H |     Name Length (7+)      |
      # +---+---------------------------+
      # |  Name String (Length octets)  |
      # +---+---------------------------+
      # | H |     Value Length (7+)     |
      # +---+---------------------------+
      # | Value String (Length octets)  |
      # +-------------------------------+
      def encode_literal(name, value, indexing = true)
        if indexing
          store(name, value)
          fb = "\x40"
        else
          fb = "\x00"
        end
        fb << encode_string(name) << encode_string(value)
      end

      # +---+---+---+---+---+---+---+---+
      # | 0 | 1 |      Index (6+)       |
      # +---+---+-----------------------+
      # | H |     Value Length (7+)     |
      # +---+---------------------------+
      # | Value String (Length octets)  |
      # +-------------------------------+
      def encode_half_indexed(index, value, indexing = true)
        if indexing
          store(fetch(index)[0], value)
          fb = encode_integer(index, 6)
          fb.setbyte(0, fb.uint8 | 0b01000000)
        else
          fb = encode_integer(index, 4)
        end
        fb << encode_string(value)
      end

      # +---+---+---+---+---+---+---+---+
      # | 1 |        Index (7+)         |
      # +---+---------------------------+
      def encode_indexed(index)
        s = encode_integer(index, 7)
        s.setbyte(0, s.uint8 | 0b10000000)
        s
      end

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
        huffman_str = Huffman.encode(str).force_encoding(__ENCODING__)
        if huffman_str.bytesize < str.bytesize
          lenstr = encode_integer(huffman_str.bytesize, 7)
          lenstr.setbyte(0, lenstr.uint8(0) | 0b10000000)
          lenstr << huffman_str
        else
          encode_integer(str.bytesize, 7) << str
        end
      end
    end
  end
end
