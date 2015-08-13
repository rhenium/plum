module Plum
  module HPACK
    module Context
      attr_reader :dynamic_table, :limit, :size

      def limit=(value)
        @limit = value
        evict
      end

      private
      def initialize(dynamic_table_limit)
        @limit = dynamic_table_limit
        @dynamic_table = []
        @size = 0
      end

      def store(name, value)
        @dynamic_table.unshift([name, value])
        @size += name.bytesize + value.to_s.bytesize + 32
        evict
      end

      def fetch(index)
        if index == 0
          raise HPACKError.new("index can't be 0")
        elsif index <= STATIC_TABLE.size
          STATIC_TABLE[index - 1]
        elsif index <= STATIC_TABLE.size + @dynamic_table.size
          @dynamic_table[index - STATIC_TABLE.size - 1]
        else
          raise HPACKError.new("invalid index: #{index}")
        end
      end

      def search(name, value)
        pr = proc {|n, v|
          n == name && (!value || v == value)
        }

        si = STATIC_TABLE.index &pr
        return si + 1 if si
        di = @dynamic_table.index &pr
        return di + STATIC_TABLE.size + 1 if di
      end

      def evict
        while @limit && @size > @limit
          name, value = @dynamic_table.pop
          @size -= name.bytesize + value.to_s.bytesize + 32
        end
      end
    end
  end
end
