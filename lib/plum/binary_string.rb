# frozen-string-literal: true

module Plum
  module BinaryString
    refine String do
      # Reads a 8-bit unsigned integer.
      # @param pos [Integer] The start position to read.
      def uint8(pos = 0)
        getbyte(pos)
      end

      # Reads a 16-bit unsigned integer.
      # @param pos [Integer] The start position to read.
      def uint16(pos = 0)
        byteslice(pos, 2).unpack("n")[0]
      end

      # Reads a 24-bit unsigned integer.
      # @param pos [Integer] The start position to read.
      def uint24(pos = 0)
        a, b = byteslice(pos, 3).unpack("nC")
        (a * 0x100) + b
      end

      # Reads a 32-bit unsigned integer.
      # @param pos [Integer] The start position to read.
      def uint32(pos = 0)
        byteslice(pos, 4).unpack("N")[0]
      end

      # Appends a 8-bit unsigned integer to this string.
      def push_uint8(val)
        self << val.chr
      end

      # Appends a 16-bit unsigned integer to this string.
      def push_uint16(val)
        self << [val].pack("n")
      end

      # Appends a 24-bit unsigned integer to this string.
      def push_uint24(val)
        self << [val / 0x100, val % 0x100].pack("nC")
      end

      # Appends a 32-bit unsigned integer to this string.
      def push_uint32(val)
        self << [val].pack("N")
      end

      alias push <<

      # Takes from beginning and cut specified *octets* from this String.
      # @param count [Integer] The amount.
      def byteshift(count)
        force_encoding(Encoding::BINARY)
        slice!(0, count)
      end

      def each_byteslice(n, &blk)
        if block_given?
          pos = 0
          while pos < self.bytesize
            yield byteslice(pos, n)
            pos += n
          end
        else
          Enumerator.new do |y|
            each_byteslice(n) {|ss| y << ss }
          end
          # I want to write `enum_for(__method__, n)`!
        end
      end

      # Splits this String into chunks.
      # @param n [Integer] max chunk bytesize
      # @return [Array<String>] the slices
      def chunk(n)
        res = []
        pos = 0
        lim = bytesize
        while pos < lim
          res << byteslice(pos, n)
          pos += n
        end
        res
      end
    end
  end
end
