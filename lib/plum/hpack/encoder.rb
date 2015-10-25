using Plum::BinaryString

module Plum
  module HPACK
    class Encoder
      include HPACK::Context

      def initialize(dynamic_table_limit, indexing: true, huffman: true)
        super(dynamic_table_limit)
        @indexing = indexing
        @huffman = huffman
      end

      def encode(headers)
        out = ""
        headers.each do |name, value|
          name = name.to_s
          value = value.to_s
          if index = search(name, value)
            out << encode_indexed(index)
          elsif index = search(name, nil)
            out << encode_half_indexed(index, value)
          else
            out << encode_literal(name, value)
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
      def encode_literal(name, value)
        if @indexing
          store(name, value)
          fb = "\x40"
        else
          fb = "\x00"
        end
        fb.force_encoding(Encoding::BINARY) << encode_string(name) << encode_string(value)
      end

      # +---+---+---+---+---+---+---+---+
      # | 0 | 1 |      Index (6+)       |
      # +---+---+-----------------------+
      # | H |     Value Length (7+)     |
      # +---+---------------------------+
      # | Value String (Length octets)  |
      # +-------------------------------+
      def encode_half_indexed(index, value)
        if @indexing
          store(fetch(index)[0], value)
          fb = encode_integer(index, 6, 0b01000000)
        else
          fb = encode_integer(index, 4, 0b00000000)
        end
        fb << encode_string(value)
      end

      # +---+---+---+---+---+---+---+---+
      # | 1 |        Index (7+)         |
      # +---+---------------------------+
      def encode_indexed(index)
        encode_integer(index, 7, 0b10000000)
      end

      def encode_integer(value, prefix_length, hmask)
        mask = (1 << prefix_length) - 1

        if value < mask
          (value + hmask).chr.force_encoding(Encoding::BINARY)
        else
          vals = [mask + hmask]
          value -= mask
          while value >= mask
            vals << (value % 0x80) + 0x80
            value /= 0x80
          end
          vals << value
          vals.pack("C*")
        end
      end

      def encode_string(str)
        if @huffman
          hs = encode_string_huffman(str)
          ps = encode_string_plain(str)
          hs.bytesize < ps.bytesize ? hs : ps
        else
          encode_string_plain(str)
        end
      end

      def encode_string_plain(str)
        encode_integer(str.bytesize, 7, 0b00000000) << str.force_encoding(Encoding::BINARY)
      end

      def encode_string_huffman(str)
        huffman_str = Huffman.encode(str)
        lenstr = encode_integer(huffman_str.bytesize, 7, 0b10000000)
        lenstr << huffman_str
      end
    end
  end
end
