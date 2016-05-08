# frozen-string-literal: true

using Plum::BinaryString
module Plum
  class Frame::Headers < Frame
    register_subclass 0x01

    # Creates a HEADERS frame.
    # @param stream_id [Integer] The stream ID.
    # @param encoded [String] Headers.
    # @param end_stream [Boolean] add END_STREAM flag
    # @param end_headers [Boolean] add END_HEADERS flag
    def initialize(stream_id, encoded, end_stream: false, end_headers: false)
      fval = end_stream ? 1 : 0
      fval += 4 if end_headers
      initialize_base(type_value: 1, stream_id: stream_id, flags_value: fval, payload: encoded)
    end

    # Splits this frame into multiple frames not to exceed MAX_FRAME_SIZE.
    # @param max [Integer] The maximum size of a frame payload.
    # @yield [Frame] The splitted frames.
    def split(max)
      return yield self if @length <= max
      first, *mid, last = @payload.chunk(max)
      yield Frame.craft(type_value: @type_value, stream_id: @stream_id, payload: first, flags_value: @flags_value & ~4)
      mid.each { |slice|
        yield Frame.craft(type: :continuation, stream_id: @stream_id, payload: slice, flags_value: 0)
      }
      yield Frame.craft(type: :continuation, stream_id: @stream_id, payload: last, flags_value: @flags_value & 4)
    end
  end
end
