# frozen-string-literal: true

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
    }.freeze

    # @!visibility private
    FRAME_TYPES_INVERSE = FRAME_TYPES.invert.freeze

    FRAME_FLAGS = {
      data: {
        end_stream:   0x01,
        padded:       0x08
      }.freeze,
      headers: {
        end_stream:   0x01,
        end_headers:  0x04,
        padded:       0x08,
        priority:     0x20
      }.freeze,
      priority: {}.freeze,
      rst_stream: {}.freeze,
      settings: {
        ack:          0x01
      }.freeze,
      push_promise: {
        end_headers:  0x04,
        padded:       0x08
      }.freeze,
      ping: {
        ack:          0x01
      }.freeze,
      goaway: {}.freeze,
      window_update: {}.freeze,
      continuation: {
        end_headers:  0x04
      }.freeze
    }.freeze

    # @!visibility private
    FRAME_FLAGS_MAP = FRAME_FLAGS.values.inject(:merge).freeze

    SETTINGS_TYPE = {
      header_table_size:      0x01,
      enable_push:            0x02,
      max_concurrent_streams: 0x03,
      initial_window_size:    0x04,
      max_frame_size:         0x05,
      max_header_list_size:   0x06
    }.freeze

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
    # [Integer] Stream Identifier. Unsigned 31-bit integer
    attr_reader :stream_id
    # [String] The payload. Value is frozen.
    attr_reader :payload

    def initialize(type: nil, type_value: nil, flags: nil, flags_value: nil, stream_id: nil, payload: nil)
      @payload = payload || ""
      @length = @payload.bytesize
      @type_value = type_value or self.type = type
      @flags_value = flags_value or self.flags = flags
      @stream_id = stream_id or raise ArgumentError.new("stream_id is necessary")
    end

    # Returns the length of payload.
    # @return [Integer] The length.
    def length
      @length
    end

    # Returns the type of the frame in Symbol.
    # @return [Symbol] The type.
    def type
      FRAME_TYPES_INVERSE[@type_value] || ("unknown_%02x" % @type_value).to_sym
    end

    # Sets the frame type.
    # @param value [Symbol] The type.
    def type=(value)
      @type_value = FRAME_TYPES[value] or raise ArgumentError.new("unknown frame type: #{value}")
    end

    # Returns the set flags on the frame.
    # @return [Array<Symbol>] The flags.
    def flags
      fs = FRAME_FLAGS[type]
      [0x01, 0x02, 0x04, 0x08, 0x10, 0x20, 0x40, 0x80]
        .select {|v| @flags_value & v > 0 }
        .map {|val| fs && fs.key(val) || ("unknown_%02x" % val).to_sym }
    end

    # Sets the frame flags.
    # @param values [Array<Symbol>] The flags.
    def flags=(values)
      val = 0
      FRAME_FLAGS_MAP.values_at(*values).each { |c|
        val |= c if c
      }
      @flags_value = val
    end

    # Frame#flag_name?() == Frame#flags().include?(:flag_name)
    FRAME_FLAGS_MAP.each { |name, value|
      class_eval <<-EOS, __FILE__, __LINE__ + 1
        def #{name}?
          @flags_value & #{value} > 0
        end
      EOS
    }

    # Assembles the frame into binary representation.
    # @return [String] Binary representation of this frame.
    def assemble
      [length / 0x100, length % 0x100,
       @type_value,
       @flags_value,
       @stream_id].pack("nCCCN") << @payload
    end

    # @private
    def inspect
      "#<Plum::Frame:0x%04x} length=%d, type=%p, flags=%p, stream_id=0x%04x, payload=%p>" % [__id__, length, type, flags, stream_id, payload]
    end

    # Parses a frame from given buffer. It changes given buffer.
    # @param buffer [String] The buffer stored the data received from peer. Encoding must be Encoding::BINARY.
    # @return [Frame, nil] The parsed frame or nil if the buffer is imcomplete.
    def self.parse!(buffer)
      return nil if buffer.bytesize < 9 # header: 9 bytes
      length = buffer.uint24
      return nil if buffer.bytesize < 9 + length

      cur = buffer.byteshift(9 + length)
      type_value, flags_value, r_sid = cur.byteslice(3, 6).unpack("CCN")
      # r = r_sid >> 31 # currently not used
      stream_id = r_sid # & ~(1 << 31)

      self.new(type_value: type_value,
               flags_value: flags_value,
               stream_id: stream_id,
               payload: cur.byteslice(9, length)).freeze
    end
  end
end
