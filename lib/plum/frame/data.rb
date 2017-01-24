using Plum::BinaryString

module Plum
  class Frame::Data < Frame
    register_subclass 0x00

    # Creates a DATA frame.
    # @param stream_id [Integer] The stream ID.
    # @param payload [String] Payload.
    # @param end_stream [Boolean] add END_STREAM flag
    def initialize(stream_id, payload = "", end_stream: false)
      payload = payload.b if payload&.encoding != Encoding::BINARY
      fval = end_stream ? 1 : 0
      initialize_base(type_value: 0, stream_id: stream_id, flags_value: fval, payload: payload)
    end

    # Splits this frame into multiple frames not to exceed MAX_FRAME_SIZE.
    # @param max [Integer] The maximum size of a frame payload.
    # @yield [Frame] The splitted frames.
    def split(max)
      return yield self if @length <= max
      first, *mid, last = @payload.chunk(max)
      yield Frame.craft(type_value: 0, stream_id: @stream_id, payload: first, flags_value: @flags_value & ~1)
      mid.each { |slice|
        yield Frame.craft(type_value: 0, stream_id: @stream_id, payload: slice, flags_value: 0)
      }
      yield Frame.craft(type_value: 0, stream_id: @stream_id, payload: last, flags_value: @flags_value & 1)
    end
  end
end
