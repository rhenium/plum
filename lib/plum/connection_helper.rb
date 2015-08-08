using Plum::BinaryString

module Plum
  module ConnectionHelper
    # Sends local settings to the peer.
    #
    # @param kwargs [Hash<Symbol, Integer>]
    def settings(**kwargs)
      send_immediately Frame.settings(**kwargs)
      update_local_settings(kwargs)
    end

    # Sends a PING frame to the peer.
    #
    # @param data [String] Must be 8 octets.
    # @raise [ArgumentError] If the data is not 8 octets.
    def ping(data = "plum\x00\x00\x00\x00")
      send_immediately Frame.ping(data)
    end
  end
end
