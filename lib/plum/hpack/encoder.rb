module Plum
  module HPACK
    class Encoder
      attr_reader :context

      def initialize(dynamic_table_limit)
        @context = Context.new(dynamic_table_limit)
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
        out = "".b
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

        if value < mask
          [value].pack("C").b
        else
          bytes = [mask]
          value -= mask
          while value >= mask
            bytes << (value % 0b10000000) + 0b10000000
            value >>= 7
          end
          bytes << value
 
          bytes.pack("C*").b
        end
      end
    end
  end
end
