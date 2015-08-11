using Plum::BinaryString

module Plum
  module FrameUtils
    # Splits the frame into multiple frames if the payload size exceeds max size.
    #
    # @param max [Integer] The maximum size of a frame payload.
    # @return [Array<Frame>] The splitted frames.
    def split_data(max)
      return [self] if self.length <= max
      raise "Frame type must be DATA" unless self.type == :data

      fragments = []
      while (pos = fragments.size * max) <= self.length # zero
        fragments << self.payload.byteslice(pos, max)
      end

      frames = []
      last = Frame.data(stream_id, fragments.pop, *(self.flags & [:end_stream]))
      fragments.each do |fragment|
        frames << Frame.data(stream_id, fragment, *(self.flags - [:end_stream]))
      end
      frames << last
      frames
    end

    def split_headers(max)
      return [self] if self.length <= max
      raise "Frame type must be DATA" unless [:headers, :push_promise].include?(self.type)

      fragments = []
      while (pos = fragments.size * max) < self.length # zero
        fragments << self.payload.byteslice(pos, max)
      end

      frames = []
      frames << Frame.new(type_value: self.type_value, flags: self.flags - [:end_headers], stream_id: self.stream_id, payload: fragments.shift)
      if fragments.size > 0
        last = Frame.continuation(stream_id, fragments.pop, *(self.flags & [:end_headers]))
        fragments.each do |fragment|
          frames << Frame.continuation(stream_id, fragment)
        end
        frames << last
      end
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
