# -*- frozen-string-literal: true -*-
using Plum::BinaryString

module Plum
  module FrameUtils
    # Splits this frame into multiple frames not to exceed MAX_FRAME_SIZE.
    # @param max [Integer] The maximum size of a frame payload.
    # @yield [Frame] The splitted frames.
    def split(max)
      return yield self if @length <= max
      first, *mid, last = @payload.chunk(max)
      case type
      when :data
        yield Frame.new(type_value: 0, stream_id: @stream_id, payload: first, flags_value: @flags_value & ~1)
        mid.each { |slice|
          yield Frame.new(type_value: 0, stream_id: @stream_id, payload: slice, flags_value: 0)
        }
        yield Frame.new(type_value: 0, stream_id: @stream_id, payload: last, flags_value: @flags_value & 1)
      when :headers, :push_promise
        yield Frame.new(type_value: @type_value, stream_id: @stream_id, payload: first, flags_value: @flags_value & ~4)
        mid.each { |slice|
          yield Frame.new(type: :continuation, stream_id: @stream_id, payload: slice, flags_value: 0)
        }
        yield Frame.new(type: :continuation, stream_id: @stream_id, payload: last, flags_value: @flags_value & 4)
      else
        raise NotImplementedError.new("frame split of frame with type #{type} is not supported")
      end
    end

    # Parses SETTINGS frame payload. Ignores unknown settings type (see RFC7540 6.5.2).
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
