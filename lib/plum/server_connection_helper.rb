using Plum::BinaryString

module Plum
  module ServerConnectionHelper
    # Sends local settings to the peer.
    #
    # @param kwargs [Hash<Symbol, Integer>]
    def settings(**kwargs)
      payload = kwargs.inject("") {|payload, (key, value)|
        id = Frame::SETTINGS_TYPE[key] or raise ArgumentError.new("invalid settings type")
        payload.push_uint16(id)
        payload.push_uint32(value)
      }
      send Frame.new(type: :settings,
                     stream_id: 0,
                     payload: payload)
      update_local_settings(kwargs)
    end

    # Sends a PING frame to the peer.
    #
    # @param data [String] Must be 8 octets.
    # @raise [ArgumentError] If the data is not 8 octets.
    def ping(data = "plum\x00\x00\x00\x00")
      raise ArgumentError.new("data must be 8 octets") if data.bytesize != 8
      send Frame.new(type: :ping,
                     stream_id: 0,
                     payload: data)
    end
  end
end
