using Plum::BinaryString

module Plum
  class Frame::Ping < Frame
    register_subclass 0x06

    # Creates a PING frame.
    # @overload ping(ack, payload)
    #   @param ack [Symbol] Pass :ack to create an ACK frame.
    #   @param payload [String] 8 bytes length data to send.
    # @overload ping(payload = "plum\x00\x00\x00\x00")
    #   @param payload [String] 8 bytes length data to send.
    def initialize(arg1 = "plum\x00\x00\x00\x00".b, arg2 = nil)
      if !arg2
        raise ArgumentError.new("data must be 8 octets") if arg1.bytesize != 8
        arg1 = arg1.b if arg1.encoding != Encoding::BINARY
        initialize_base(type: :ping, stream_id: 0, payload: arg1)
      else
        initialize_base(type: :ping, stream_id: 0, flags: [:ack], payload: arg2)
      end
    end
  end
end
