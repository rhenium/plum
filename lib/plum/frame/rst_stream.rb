# frozen-string-literal: true

using Plum::BinaryString
module Plum
  class Frame::RstStream < Frame
    register_subclass 0x03

    # Creates a RST_STREAM frame.
    # @param stream_id [Integer] The stream ID.
    # @param error_type [Symbol] The error type defined in RFC 7540 Section 7.
    def initialize(stream_id, error_type)
      payload = "".b.push_uint32(HTTPError::ERROR_CODES[error_type])
      initialize_base(type: :rst_stream, stream_id: stream_id, payload: payload)
    end
  end
end
