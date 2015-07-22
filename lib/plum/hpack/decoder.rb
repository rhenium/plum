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
        while str.size > 0
          headers << parse!(str)
        end
        headers.compact
      end

      private
      def read_integer!(str, prefix_length)
        mask = (1 << prefix_length) - 1
        i = str.shift(1).uint8 & mask

        if i == mask
          m = 0
          begin
            next_value = str.shift(1).uint8
            i += (next_value & ~(0b10000000)) << m
            m += 7
          end until next_value & 0b10000000 == 0
        end

        i
      end

      def read_string!(str, length, huffman)
        bin = str.shift(length)
        bin = Huffman.decode(bin) if huffman
        bin
      end

      def parse!(str)
        first_byte = str.uint8
        if first_byte & 0b10000000 == 0b10000000
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
        elsif first_byte & 0b11000000 == 0b01000000
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
            hname = (str.uint8 >> 7) == 1
            lname = read_integer!(str, 7)
            name = read_string!(str, lname, hname)
          else
            name, = fetch(index)
          end

          hval = (str.uint8 >> 7) == 1
          lval = read_integer!(str, 7)
          val = read_string!(str, lval, hval)
          store(name, val)

          [name, val]
        elsif first_byte & 0b11110000 == 0b00000000 || # without indexing
              first_byte & 0b11110000 == 0b00010000    # never indexing
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
            hname = (str.uint8 >> 7) == 1
            lname = read_integer!(str, 7)
            name = read_string!(str, lname, hname)
          else
            name, = fetch(index)
          end

          hval = (str.uint8 >> 7) == 1
          lval = read_integer!(str, 7)
          val = read_string!(str, lval, hval)

          [name, val]
        elsif first_byte & 0b11100000 == 0b00100000
          self.limit = read_integer!(str, 5)
          nil
        else
          raise HPACKError.new("invalid header firld representation")
        end
      end
    end
  end
end
