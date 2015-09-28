# -*- frozen-string-literal: true -*-
using Plum::BinaryString

module Plum
  class Frame
    extend FrameFactory
    include FrameUtils

    FRAME_TYPES = {
      data:           0x00,
      headers:        0x01,
      priority:       0x02,
      rst_stream:     0x03,
      settings:       0x04,
      push_promise:   0x05,
      ping:           0x06,
      goaway:         0x07,
      window_update:  0x08,
      continuation:   0x09
    }

    FRAME_FLAGS = {
      data: {
        end_stream:   0x01,
        padded:       0x08
      },
      headers: {
        end_stream:   0x01,
        end_headers:  0x04,
        padded:       0x08,
        priority:     0x20
      },
      priority: {},
      rst_stream: {},
      settings: {
        ack:          0x01
      },
      push_promise: {
        end_headers:  0x04,
        padded:       0x08
      },
      ping: {
        ack:          0x01
      },
      goaway: {},
      window_update: {},
      continuation: {
        end_headers:  0x04
      }
    }

    SETTINGS_TYPE = {
      header_table_size:      0x01,
      enable_push:            0x02,
      max_concurrent_streams: 0x03,
      initial_window_size:    0x04,
      max_frame_size:         0x05,
      max_header_list_size:   0x06
    }

    # RFC7540: 4.1 Frame format
    # +-----------------------------------------------+
    # |                 Length (24)                   |
    # +---------------+---------------+---------------+
    # |   Type (8)    |   Flags (8)   |
    # +-+-------------+---------------+-------------------------------+
    # |R|                 Stream Identifier (31)                      |
    # +=+=============================================================+
    # |                   Frame Payload (0...)                      ...
    # +---------------------------------------------------------------+

    # [Integer] Frame type. 8-bit
    attr_accessor :type_value
    # [Integer] Flags. 8-bit
    attr_accessor :flags_value
    # [Integer] Stream Identifier. unsigned 31-bit integer
    attr_accessor :stream_id
    # [String] The payload.
    attr_accessor :payload

    def initialize(type: nil, type_value: nil, flags: nil, flags_value: nil, stream_id: nil, payload: nil)
      self.payload = (payload || "")
      self.type_value = type_value or self.type = type
      self.flags_value = flags_value or self.flags = flags
      self.stream_id = stream_id or raise ArgumentError.new("stream_id is necessary")
    end

    # Returns the length of payload.
    # @return [Integer] The length.
    def length
      @payload.bytesize
    end

    # Returns the type of the frame in Symbol.
    # @return [Symbol] The type.
    def type
      FRAME_TYPES.key(type_value) || ("unknown_%02x" % type_value).to_sym
    end

    # Sets the frame type.
    # @param value [Symbol] The type.
    def type=(value)
      self.type_value = FRAME_TYPES[value] or raise ArgumentError.new("unknown frame type: #{value}")
    end

    # Returns the set flags on the frame.
    # @return [Array<Symbol>] The flags.
    def flags
      fs = FRAME_FLAGS[type]
      [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80]
        .select {|v| flags_value & v > 0 }
        .map {|val| fs && fs.key(val) || ("unknown_%02x" % val).to_sym }
    end

    # Sets the frame flags.
    # @param value [Array<Symbol>] The flags.
    def flags=(value)
      self.flags_value = (value && value.map {|flag| FRAME_FLAGS[self.type][flag] }.inject(:|) || 0)
    end

    # Assembles the frame into binary representation.
    # @return [String] Binary representation of this frame.
    def assemble
      bytes = String.new
      bytes.push_uint24(length)
      bytes.push_uint8(type_value)
      bytes.push_uint8(flags_value)
      bytes.push_uint32(stream_id & ~(1 << 31)) # first bit is reserved (MUST be 0)
      bytes.push(payload)
      bytes
    end

    # @private
    def inspect
      "#<Plum::Frame:0x%04x} length=%d, type=%p, flags=%p, stream_id=0x%04x, payload=%p>" % [__id__, length, type, flags, stream_id, payload]
    end

    # Parses a frame from given buffer. It changes given buffer.
    #
    # @param buffer [String] The buffer stored the data received from peer.
    # @return [Frame, nil] The parsed frame or nil if the buffer is imcomplete.
    def self.parse!(buffer)
      return nil if buffer.bytesize < 9 # header: 9 bytes
      length = buffer.uint24
      return nil if buffer.bytesize < 9 + length

      bhead = buffer.byteshift(9)
      payload = buffer.byteshift(length)

      type_value = bhead.uint8(3)
      flags_value = bhead.uint8(4)
      r_sid = bhead.uint32(5)
      r = r_sid >> 31
      stream_id = r_sid & ~(1 << 31)

      self.new(type_value: type_value,
               flags_value: flags_value,
               stream_id: stream_id,
               payload: payload).freeze
    end
  end
end
