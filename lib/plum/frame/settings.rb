# frozen-string-literal: true

using Plum::BinaryString
module Plum
  class Frame::Settings < Frame
    register_subclass 0x04

    SETTINGS_TYPE = {
      header_table_size:      0x01,
      enable_push:            0x02,
      max_concurrent_streams: 0x03,
      initial_window_size:    0x04,
      max_frame_size:         0x05,
      max_header_list_size:   0x06
    }.freeze

    # Creates a SETTINGS frame.
    # @param ack [Symbol] Pass :ack to create an ACK frame.
    # @param args [Hash<Symbol, Integer>] The settings values to send.
    def initialize(ack = nil, **args)
      payload = String.new
      args.each { |key, value|
        id = SETTINGS_TYPE[key] or raise ArgumentError.new("invalid settings type: #{key}")
        payload.push_uint16(id)
        payload.push_uint32(value)
      }
      initialize_base(type: :settings, stream_id: 0, flags: [ack], payload: payload)
    end

    # Parses SETTINGS frame payload. Ignores unknown settings type (see RFC7540 6.5.2).
    # @return [Hash<Symbol, Integer>] The parsed strings.
    def parse_settings
      settings = {}
      payload.each_byteslice(6) do |param|
        id = param.uint16
        name = SETTINGS_TYPE.key(id)
        # ignore unknown settings type
        settings[name] = param.uint32(2) if name
      end
      settings
    end
  end
end
