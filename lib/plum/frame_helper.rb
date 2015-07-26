using Plum::BinaryString

module Plum
  module FrameHelper
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
        frames << Frame.new(type_value: self.type_value, flags: self.flags.reject {|f| f == :end_headers }, stream_id: self.stream_id, payload: fragments.shift)
        if fragments.size > 0
          last = Frame.new(type: :continuation, flags: self.flags.select {|f| f == :end_headers }, stream_id: self.stream_id, payload: fragments.pop)
          fragments.each do |fragment|
            frames << Frame.new(type: :continuation, flags: self.flags.reject {|f| f == :end_headers }, stream_id: self.stream_id, payload: fragment)
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
        frames << Frame.new(type: :data, flags: self.flags.reject {|f| f == :end_stream }, stream_id: self.stream_id, payload: fragments.shift)
        if fragments.size > 0
          last = Frame.new(type: :data, flags: self.flags.select {|f| f == :end_stream }, stream_id: self.stream_id, payload: fragments.pop)
          fragments.each do |fragment|
            frames << Frame.new(type: :data, flags: self.flags.reject {|f| f == :end_stream }, stream_id: self.stream_id, payload: fragment)
          end
          frames << last
        end
        frames
      else
        raise "Frame#split is not defined for #{type}"
      end
    end
  end
end
