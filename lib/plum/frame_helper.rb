using Plum::BinaryString

module Plum
  module FrameHelper
    # Splits the frame into multiple frames if the payload size exceeds max size.
    #
    # @param max [Integer] The maximum size of a frame payload.
    # @return [Array<Frame>] The splitted frames.
    def split(max)
      if self.length <= max
        return [self]
      end

      case type
      when :headers, :push_promise
        fragments = []
        pos = 0
        while pos < self.length
          fragments << self.payload.byteslice(pos, max)
          pos += max
        end

        frames = []
        frames << Frame.new(type_value: self.type_value, flags: self.flags - [:end_headers], stream_id: self.stream_id, payload: fragments.shift)
        if fragments.size > 0
          last = Frame.new(type: :continuation, flags: self.flags & [:end_headers], stream_id: self.stream_id, payload: fragments.pop)
          fragments.each do |fragment|
            frames << Frame.new(type: :continuation, stream_id: self.stream_id, payload: fragment)
          end
          frames << last
        end
        frames
      when :data
        fragments = []
        pos = 0
        while pos <= self.length # data may be empty
          fragments << self.payload.byteslice(pos, max)
          pos += max
        end

        frames = []
        last = Frame.new(type: :data, flags: self.flags & [:end_stream], stream_id: self.stream_id, payload: fragments.pop)
        fragments.each do |fragment|
          frames << Frame.new(type: :data, flags: self.flags - [:end_stream], stream_id: self.stream_id, payload: fragment)
        end
        frames << last
        frames
      else
        raise "Frame#split is not defined for #{type}"
      end
    end

    # Parses SETTINGS frame payload. Ignores unknown settings type (see RFC7540 6.5.2).
    #
    # @return [Hash<Symbol, Integer>] The parsed strings.
    def parse_settings
      (self.length / 6).times.map {|i|
        id = self.payload.uint16(6 * i)
        val = self.payload.uint32(6 * i + 2)
        name = Frame::SETTINGS_TYPE.key(id)
        [name, val]
      }.select {|k, v| k }.to_h
    end
  end
end
