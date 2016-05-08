# frozen-string-literal: true

using Plum::BinaryString
module Plum
  class Frame::WindowUpdate < Frame
    register_subclass 0x08

    # Creates a WINDOW_UPDATE frame.
    # @param stream_id [Integer] the stream ID or 0.
    # @param wsi [Integer] the amount to increase
    def initialize(stream_id, wsi)
      payload = String.new.push_uint32(wsi)
      initialize_base(type: :window_update, stream_id: stream_id, payload: payload)
    end
  end
end
