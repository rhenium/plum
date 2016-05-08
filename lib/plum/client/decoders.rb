module Plum
  module Decoders
    class Base
      def decode(chunk)
        chunk
      end

      def finish
      end
    end

    # `deflate` is not just deflate, wrapped by zlib format (RFC 1950)
    class Deflate < Base
      def initialize
        @inflate = Zlib::Inflate.new(Zlib::MAX_WBITS)
      end

      def decode(chunk)
        @inflate.inflate(chunk)
      rescue Zlib::Error
        raise DecoderError.new("failed to decode chunk", $!)
      end

      def finish
        @inflate.finish
      rescue Zlib::Error
        raise DecoderError.new("failed to finalize", $!)
      end
    end

    class GZip < Base
      def initialize
        @stream = Zlib::Inflate.new(Zlib::MAX_WBITS + 16)
      end

      def decode(chunk)
        @stream.inflate(chunk)
      rescue Zlib::Error
        raise DecoderError.new("failed to decode chunk", $!)
      end

      def finish
        @stream.finish
      rescue Zlib::Error
        raise DecoderError.new("failed to finalize", $!)
      end
    end

    DECODERS = { "gzip" => GZip, "deflate" => Deflate }
  end
end
