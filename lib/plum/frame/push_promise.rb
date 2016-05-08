# frozen-string-literal: true

using Plum::BinaryString
module Plum
  class Frame::PushPromise < Frame
    register_subclass 0x05

    # Creates a PUSH_PROMISE frame.
    # @param stream_id [Integer] The stream ID.
    # @param new_id [Integer] The stream ID to create.
    # @param encoded [String] Request headers.
    # @param end_headers [Boolean] add END_HEADERS flag
    def initialize(stream_id, new_id, encoded, end_headers: false)
      payload = String.new.push_uint32(new_id)
                          .push(encoded)
      fval = end_headers ? 4 : 0
      initialize_base(type: :push_promise, stream_id: stream_id, flags_value: fval, payload: payload)
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
