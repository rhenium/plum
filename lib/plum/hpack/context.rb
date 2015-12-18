# -*- frozen-string-literal: true -*-
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
        value = value.to_s
        @dynamic_table.unshift([name.freeze, value.freeze])
        @size += name.bytesize + value.bytesize + 32
        evict
      end

      def fetch(index)
        if index == 0
          raise HPACKError.new("index can't be 0")
        elsif index <= STATIC_TABLE_SIZE
            STATIC_TABLE[index - 1]
        elsif index <= STATIC_TABLE.size + @dynamic_table.size
          @dynamic_table[index - STATIC_TABLE_SIZE - 1]
        else
          raise HPACKError.new("invalid index: #{index}")
        end
      end

      def search(name, value)
        si = STATIC_TABLE.index { |n, v| n == name && v == value }
        return si + 1 if si
        di = @dynamic_table.index { |n, v| n == name && v == value }
        return di + STATIC_TABLE_SIZE + 1 if di
      end

      def search_half(name)
        si = STATIC_TABLE.index { |n, v| n == name }
        return si + 1 if si
        di = @dynamic_table.index { |n, v| n == name }
        return di + STATIC_TABLE_SIZE + 1 if di
      end

      def evict
        while @size > @limit
          name, value = @dynamic_table.pop
          @size -= name.bytesize + value.bytesize + 32
        end
      end
    end
  end
end
