# -*- frozen-string-literal: true -*-
using Plum::BinaryString

module Plum
  module FrameUtils
    # Splits the DATA frame into multiple frames if the payload size exceeds max size.
    #
    # @param max [Integer] The maximum size of a frame payload.
    # @return [Array<Frame>] The splitted frames.
    def split_data(max)
      return [self] if self.length <= max
      raise "Frame type must be DATA" unless self.type == :data

      fragments = self.payload.each_byteslice(max).to_a
      frames = fragments.map {|fragment| Frame.new(type: :data, flags: [], stream_id: self.stream_id, payload: fragment) }
      frames.first.flags = self.flags - [:end_stream]
      frames.last.flags = self.flags & [:end_stream]
      frames
    end

    # Splits the HEADERS or PUSH_PROMISE frame into multiple frames if the payload size exceeds max size.
    #
    # @param max [Integer] The maximum size of a frame payload.
    # @return [Array<Frame>] The splitted frames.
    def split_headers(max)
      return [self] if self.length <= max
      raise "Frame type must be HEADERS or PUSH_PROMISE" unless [:headers, :push_promise].include?(self.type)

      fragments = self.payload.each_byteslice(max).to_a
      frames = fragments.map {|fragment| Frame.new(type: :continuation, flags: [], stream_id: self.stream_id, payload: fragment) }
      frames.first.type_value = self.type_value
      frames.first.flags = self.flags - [:end_headers]
      frames.last.flags = self.flags & [:end_headers]
      frames
    end

    # Parses SETTINGS frame payload. Ignores unknown settings type (see RFC7540 6.5.2).
    #
    # @return [Hash<Symbol, Integer>] The parsed strings.
    def parse_settings
      settings = {}
      payload.each_byteslice(6) do |param|
        id = param.uint16
        name = Frame::SETTINGS_TYPE.key(id)
        # ignore unknown settings type
        settings[name] = param.uint32(2) if name
      end
      settings
    end
  end
end
