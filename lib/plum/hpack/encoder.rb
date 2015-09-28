# -*- frozen-string-literal: true -*-
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
        out = String.new
        headers.each do |name, value|
          name = name.to_s.b
          value = value.to_s.b
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
        fb.b << encode_string(name) << encode_string(value)
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
        out = String.new

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
        out.force_encoding(Encoding::BINARY)
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
        encode_integer(str.bytesize, 7) << str.force_encoding(Encoding::BINARY)
      end

      def encode_string_huffman(str)
        huffman_str = Huffman.encode(str)
        lenstr = encode_integer(huffman_str.bytesize, 7)
        lenstr.setbyte(0, lenstr.uint8(0) | 0b10000000)
        lenstr.force_encoding(Encoding::BINARY) << huffman_str
      end
    end
  end
end
