using Plum::BinaryString
module Plum
  class Frame::Continuation < Frame
    register_subclass 0x09

    # Creates a CONTINUATION frame.
    # @param stream_id [Integer] The stream ID.
    # @param payload [String] Payload.
    # @param end_headers [Boolean] add END_HEADERS flag
    def initialize(stream_id, payload, end_headers: false)
      initialize_base(type: :continuation, stream_id: stream_id, flags_value: (end_headers ? 4 : 0), payload: payload)
    end
  end
end
