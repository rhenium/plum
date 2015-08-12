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
        mask = (1 << prefix_length) - 1
        ret = str.byteshift(1).uint8 & mask

        if ret == mask
          loop.with_index do |_, i|
            next_value = str.byteshift(1).uint8
            ret += (next_value & ~(0b10000000)) << (7 * i)
            break if next_value & 0b10000000 == 0
          end
        end

        ret
      end

      def read_string!(str)
        huffman = (str.uint8 >> 7) == 1
        length = read_integer!(str, 7)
        bin = str.byteshift(length)
        bin = Huffman.decode(bin) if huffman
        bin
      end

      def parse_indexed!(str)
        # indexed
        # +---+---+---+---+---+---+---+---+
        # | 1 |        Index (7+)         |
        # +---+---------------------------+
        index = read_integer!(str, 7)
        if index == 0
          raise HPACKError.new("index can't be 0 in indexed heaeder field representation")
        else
          fetch(index)
        end
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
