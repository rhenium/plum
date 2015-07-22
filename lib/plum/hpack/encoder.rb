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
        out = "".force_encoding(Encoding::BINARY)
        headers.each do |name, value|
          name = name.to_s; value = value.to_s
          out << "\x00"
          out << encode_integer(name.bytesize, 7)
          out << name
          out << encode_integer(value.bytesize, 7)
          out << value
        end
        out
      end

      private
      def encode_integer(value, prefix_length)
        mask = (1 << prefix_length) - 1
        out = "".force_encoding(Encoding::BINARY)

        if value < mask
          out.push_uint8(value)
        else
          bytes = [mask]
          value -= mask
          out.push_uint8(mask)
          while value >= mask
            out.push_uint8((value % 0b10000000) + 0b10000000)
            value >>= 7
          end
          out.push_uint8(value)
        end
      end
    end
  end
end
