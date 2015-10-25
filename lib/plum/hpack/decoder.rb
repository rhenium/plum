using Plum::BinaryString

module Plum
  module HPACK
    class Decoder
      include HPACK::Context

      def initialize(dynamic_table_limit)
        super
      end

      def decode(str)
        headers = []
        pos = 0
        lpos = str.bytesize
        while pos < lpos
          l, succ = parse(str, pos)
          pos += succ
          headers << l if l
        end
        headers
      end

      private
      def parse(str, pos)
        first_byte = str.uint8(pos)
        if first_byte >= 0x80 # 0b1XXXXXXX
          parse_indexed(str, pos)
        elsif first_byte >= 0x40 # 0b01XXXXXX
          parse_indexing(str, pos)
        elsif first_byte >= 0x20 # 0b001XXXXX
          self.limit, succ = read_integer(str, pos, 5)
          [nil, succ]
        else # 0b0000XXXX (without indexing) or 0b0001XXXX (never indexing)
          parse_no_indexing(str, pos)
        end
      end

      def read_integer(str, pos, prefix_length)
        raise HPACKError.new("integer: end of buffer") if str.empty?
        first_byte = str.uint8(pos)

        mask = (1 << prefix_length) - 1
        ret = first_byte & mask
        return [ret, 1] if ret != mask

        octets = 0
        while next_value = str.uint8(pos + octets + 1)
          ret += (next_value % 0x80) << (7 * octets)
          octets += 1

          if next_value < 0x80
            return [ret, 1 + octets]
          elsif octets == 4 # RFC 7541 5.1 tells us that we MUST have limitation. at least > 2 ** 28
            raise HPACKError.new("integer: too large integer")
          end
        end

        raise HPACKError.new("integer: end of buffer")
      end

      def read_string(str, pos)
        raise HPACKError.new("string: end of buffer") if str.empty?
        first_byte = str.uint8(pos)

        huffman = first_byte > 0x80
        length, ilen = read_integer(str, pos, 7)
        raise HTTPError.new("string: end of buffer") if str.bytesize < length

        bin = str.byteslice(pos + ilen, length)
        if huffman
          [Huffman.decode(bin), ilen + length]
        else
          [bin, ilen + length]
        end
      end

      def parse_indexed(str, pos)
        # indexed
        # +---+---+---+---+---+---+---+---+
        # | 1 |        Index (7+)         |
        # +---+---------------------------+
        index, succ = read_integer(str, pos, 7)
        [fetch(index), succ]
      end

      def parse_indexing(str, pos)
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
        index, ilen = read_integer(str, pos, 6)
        if index == 0
          name, nlen = read_string(str, pos + ilen)
        else
          name, = fetch(index)
          nlen = 0
        end

        val, vlen = read_string(str, pos + ilen + nlen)
        store(name, val)

        [[name, val], ilen + nlen + vlen]
      end

      def parse_no_indexing(str, pos)
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
        index, ilen = read_integer(str, pos, 4)
        if index == 0
          name, nlen = read_string(str, pos + ilen)
        else
          name, = fetch(index)
          nlen = 0
        end

        val, vlen = read_string(str, pos + ilen + nlen)

        [[name, val], ilen + nlen + vlen]
      end
    end
  end
end
