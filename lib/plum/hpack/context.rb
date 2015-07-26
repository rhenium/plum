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
        STATIC_TABLE[index - 1] || @dynamic_table[index - STATIC_TABLE.size - 1] or raise HPACKError.new("invalid index: #{index}")
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
