# -*- frozen-string-literal: true -*-
using Plum::BinaryString

module Plum
  module ConnectionUtils
    # Sends local settings to the peer.
    # @param kwargs [Hash<Symbol, Integer>]
    def settings(**kwargs)
      send_immediately Frame.settings(**kwargs)
      update_local_settings(kwargs)
    end

    # Sends a PING frame to the peer.
    # @param data [String] Must be 8 octets.
    # @raise [ArgumentError] If the data is not 8 octets.
    def ping(data = "plum\x00\x00\x00\x00")
      send_immediately Frame.ping(data)
    end

    # Sends GOAWAY frame to the peer and closes the connection.
    # @param error_type [Symbol] The error type to be contained in the GOAWAY frame.
    def goaway(error_type = :no_error)
      last_id = @max_stream_ids.max
      send_immediately Frame.goaway(last_id, error_type)
    end

    # Returns whether peer enables server push or not
    def push_enabled?
      @remote_settings[:enable_push] == 1
    end

    private
    def update_local_settings(new_settings)
      old_settings = @local_settings.dup
      @local_settings.merge!(new_settings)

      @hpack_decoder.limit = @local_settings[:header_table_size]
      update_recv_initial_window_size(@local_settings[:initial_window_size] - old_settings[:initial_window_size])
    end
  end
end
