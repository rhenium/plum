# frozen-string-literal: true

using Plum::BinaryString

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
        .select { |v| @flags_value & v > 0 }
        .map { |val| fs && fs.key(val) || ("unknown_%02x" % val).to_sym }
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

    # Creates a RST_STREAM frame.
    # @param stream_id [Integer] The stream ID.
    # @param error_type [Symbol] The error type defined in RFC 7540 Section 7.
    def self.rst_stream(stream_id, error_type)
      payload = String.new.push_uint32(HTTPError::ERROR_CODES[error_type])
      Frame.new(type: :rst_stream, stream_id: stream_id, payload: payload)
    end

    # Creates a GOAWAY frame.
    # @param last_id [Integer] The biggest processed stream ID.
    # @param error_type [Symbol] The error type defined in RFC 7540 Section 7.
    # @param message [String] Additional debug data.
    # @see RFC 7540 Section 6.8
    def self.goaway(last_id, error_type, message = "")
      payload = String.new.push_uint32(last_id)
                          .push_uint32(HTTPError::ERROR_CODES[error_type])
                          .push(message)
      Frame.new(type: :goaway, stream_id: 0, payload: payload)
    end

    # Creates a SETTINGS frame.
    # @param ack [Symbol] Pass :ack to create an ACK frame.
    # @param args [Hash<Symbol, Integer>] The settings values to send.
    def self.settings(ack = nil, **args)
      payload = String.new
      args.each { |key, value|
        id = Frame::SETTINGS_TYPE[key] or raise ArgumentError.new("invalid settings type")
        payload.push_uint16(id)
        payload.push_uint32(value)
      }
      Frame.new(type: :settings, stream_id: 0, flags: [ack], payload: payload)
    end

    # Creates a PING frame.
    # @overload ping(ack, payload)
    #   @param ack [Symbol] Pass :ack to create an ACK frame.
    #   @param payload [String] 8 bytes length data to send.
    # @overload ping(payload = "plum\x00\x00\x00\x00")
    #   @param payload [String] 8 bytes length data to send.
    def self.ping(arg1 = "plum\x00\x00\x00\x00".b, arg2 = nil)
      if !arg2
        raise ArgumentError.new("data must be 8 octets") if arg1.bytesize != 8
        arg1 = arg1.b if arg1.encoding != Encoding::BINARY
        Frame.new(type: :ping, stream_id: 0, payload: arg1)
      else
        Frame.new(type: :ping, stream_id: 0, flags: [:ack], payload: arg2)
      end
    end

    # Creates a DATA frame.
    # @param stream_id [Integer] The stream ID.
    # @param payload [String] Payload.
    # @param end_stream [Boolean] add END_STREAM flag
    def self.data(stream_id, payload = "", end_stream: false)
      payload = payload.b if payload&.encoding != Encoding::BINARY
      fval = end_stream ? 1 : 0
      Frame.new(type_value: 0, stream_id: stream_id, flags_value: fval, payload: payload)
    end

    # Creates a HEADERS frame.
    # @param stream_id [Integer] The stream ID.
    # @param encoded [String] Headers.
    # @param end_stream [Boolean] add END_STREAM flag
    # @param end_headers [Boolean] add END_HEADERS flag
    def self.headers(stream_id, encoded, end_stream: false, end_headers: false)
      fval = end_stream ? 1 : 0
      fval += 4 if end_headers
      Frame.new(type_value: 1, stream_id: stream_id, flags_value: fval, payload: encoded)
    end

    # Creates a PUSH_PROMISE frame.
    # @param stream_id [Integer] The stream ID.
    # @param new_id [Integer] The stream ID to create.
    # @param encoded [String] Request headers.
    # @param end_headers [Boolean] add END_HEADERS flag
    def self.push_promise(stream_id, new_id, encoded, end_headers: false)
      payload = String.new.push_uint32(new_id)
                          .push(encoded)
      fval = end_headers ? 4 : 0
      Frame.new(type: :push_promise, stream_id: stream_id, flags_value: fval, payload: payload)
    end

    # Creates a CONTINUATION frame.
    # @param stream_id [Integer] The stream ID.
    # @param payload [String] Payload.
    # @param end_headers [Boolean] add END_HEADERS flag
    def self.continuation(stream_id, payload, end_headers: false)
      Frame.new(type: :continuation, stream_id: stream_id, flags_value: (end_headers ? 4 : 0), payload: payload)
    end
  end
end
