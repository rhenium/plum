# -*- frozen-string-literal: true -*-
using Plum::BinaryString

module Plum
  module HPACK
    class Decoder
      include HPACK::Context

      def initialize(dynamic_table_limit)
        super
      end

      def decode(str)
        str = str.dup
        headers = []
        headers << parse!(str) while str.size > 0
        headers.compact
      end

      private
      def parse!(str)
        first_byte = str.uint8
        if first_byte >= 128 # 0b1XXXXXXX
          parse_indexed!(str)
        elsif first_byte >= 64 # 0b01XXXXXX
          parse_indexing!(str)
        elsif first_byte >= 32 # 0b001XXXXX
          self.limit = read_integer!(str, 5)
          nil
        else # 0b0000XXXX (without indexing) or 0b0001XXXX (never indexing)
          parse_no_indexing!(str)
        end
      end

      def read_integer!(str, prefix_length)
        first_byte = str.byteshift(1).uint8
        raise HPACKError.new("integer: end of buffer") unless first_byte

        mask = (1 << prefix_length) - 1
        ret = first_byte & mask
        return ret if ret < mask

        octets = 0
        while next_value = str.byteshift(1).uint8
          ret += (next_value & 0b01111111) << (7 * octets)
          octets += 1

          if next_value < 128
            return ret
          elsif octets == 4 # RFC 7541 5.1 tells us that we MUST have limitation. at least > 2 ** 28
            raise HPACKError.new("integer: too large integer")
          end
        end

        raise HPACKError.new("integer: end of buffer")
      end

      def read_string!(str)
        first_byte = str.uint8
        raise HPACKError.new("string: end of buffer") unless first_byte

        huffman = (first_byte >> 7) == 1
        length = read_integer!(str, 7)
        bin = str.byteshift(length)

        raise HTTPError.new("string: end of buffer") if bin.bytesize < length
        bin = Huffman.decode(bin) if huffman
        bin
      end

      def parse_indexed!(str)
        # indexed
        # +---+---+---+---+---+---+---+---+
        # | 1 |        Index (7+)         |
        # +---+---------------------------+
        index = read_integer!(str, 7)
        fetch(index)
      end

      def parse_indexing!(str)
        # +---+---+---+---+---+---+---+---+
        # | 0 | 1 |      Index (6+)       |
        # +---+---+-----------------------+
        # | H |     Value Length (7+)     |
        # +---+---------------------------+
        # | Value String (Length octets)  |
        # +-------------------------------+
        # or
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
        index = read_integer!(str, 6)
        if index == 0
          name = read_string!(str)
        else
          name, = fetch(index)
        end

        val = read_string!(str)
        store(name, val)

        [name, val]
      end

      def parse_no_indexing!(str)
        # +---+---+---+---+---+---+---+---+
        # | 0 | 0 | 0 |0,1|  Index (4+)   |
        # +---+---+-----------------------+
        # | H |     Value Length (7+)     |
        # +---+---------------------------+
        # | Value String (Length octets)  |
        # +-------------------------------+
        # or
        # +---+---+---+---+---+---+---+---+
        # | 0 | 0 | 0 |0,1|       0       |
        # +---+---+-----------------------+
        # | H |     Name Length (7+)      |
        # +---+---------------------------+
        # |  Name String (Length octets)  |
        # +---+---------------------------+
        # | H |     Value Length (7+)     |
        # +---+---------------------------+
        # | Value String (Length octets)  |
        # +-------------------------------+
        index = read_integer!(str, 4)
        if index == 0
          name = read_string!(str)
        else
          name, = fetch(index)
        end

        val = read_string!(str)

        [name, val]
      end
    end
  end
end
