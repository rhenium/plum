module Plum
  module HPACK
    class Context
      attr_reader :dynamic_table

      def initialize(limit = nil)
        @dynamic_table = []
        @size = 0
        @limit = limit # TODO SETTINGS_HEADER_TABLE_SIZE
      end

      def evict
        while @limit && @size > @limit
          name, value = @dynamic_table.pop
          @size -= name.bytesize + value.to_s.bytesize + 32
        end
      end

      def add(name, value)
        @dynamic_table.unshift([name, value])
        @size += name.bytesize + value.to_s.bytesize + 32
        evict
      end

      def fetch(index)
        STATIC_TABLE[index - 1] || @dynamic_table[index - STATIC_TABLE.size - 1] or raise HPACKError.new("invalid index: #{index}")
      end

      def limit=(value)
        @limit = value
        evict
      end
    end
  end
end
