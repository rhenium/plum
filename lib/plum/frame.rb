module Plum
  class Frame
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

    # [Integer] The length of payload. unsigned 24-bit integer
    attr_reader :length
    # [Integer] Frame type. 8-bit
    attr_reader :type_value
    # [Integer] Flags. 8-bit
    attr_reader :flags_value
    # [Integer] Stream Identifier. unsigned 31-bit integer
    attr_reader :stream_id
    # [String] The payload.
    attr_reader :payload

    def initialize(length: nil, type: nil, type_value: nil, flags: nil, flags_value: nil, stream_id: nil, payload: nil)
      @payload = payload.to_s
      @length = length || @payload.bytesize
      @type_value = type_value || FRAME_TYPES[type] or raise ArgumentError.new("type_value or type is necessary")
      @flags_value = flags_value || (flags && flags.map {|flag| FRAME_FLAGS[type][flag] }.inject(:|)) || 0
      @stream_id = stream_id or raise ArgumentError.new("stream_id is necessary")
    end

    def type
      FRAME_TYPES.key(type_value)
    end

    def flags
      FRAME_FLAGS[type].select {|name, value| value & flags_value > 0 }.map {|name, value| name }
    end

    def assemble
      bytes = ""
      bytes << [length].pack("N")[1, 3] # last 3*8 bits
      bytes << [type_value].pack("C")
      bytes << [flags_value].pack("C")
      bytes << [stream_id & ~(1 << 31)].pack("N") # first bit is reserved (MUST be 0)
      bytes << payload
      bytes
    end

    def inspect
      "#<Plum::Frame:0x#{__id__.to_s(16)} length=#{length.inspect}, type=#{type.inspect}, flags=#{flags.inspect}, stream_id=0x#{stream_id.to_s(16)}, payload=#{payload.inspect}>"
    end

    def self.parse!(buffer)
      return nil if buffer.size < 9 # header: 9 bytes
      bhead = buffer[0, 9]
      length = ("\x00" + bhead[0, 3]).unpack("N")[0]
      return nil if buffer.size < 9 + length

      payload = buffer.slice!(0...(9 + length))[9, length]
      type = bhead[3, 1].unpack("C")[0]
      flags = bhead[4, 1].unpack("C")[0]
      r_sid = bhead[5, 4].unpack("N")[0]
      r = r_sid >> 31
      stream_id = r_sid & ~(1 << 31)

      self.new(length: length, type_value: type, flags_value: flags, stream_id: stream_id, payload: payload)
    end
  end
end
