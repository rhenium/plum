using Plum::BinaryString

module Plum
  class Frame::Goaway < Frame
    register_subclass 0x07

    # Creates a GOAWAY frame.
    # @param last_id [Integer] The biggest processed stream ID.
    # @param error_type [Symbol] The error type defined in RFC 7540 Section 7.
    # @param message [String] Additional debug data.
    # @see RFC 7540 Section 6.8
    def initialize(last_id, error_type, message = "")
      payload = "".b.push_uint32(last_id)
                          .push_uint32(HTTPError::ERROR_CODES[error_type])
                          .push(message)
      initialize_base(type: :goaway, stream_id: 0, payload: payload)
    end
  end
end
