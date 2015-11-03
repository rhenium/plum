# -*- frozen-string-literal: true -*-
using Plum::BinaryString
module Plum
  class ServerConnection < Connection
    private
    def negotiate!
      unless CLIENT_CONNECTION_PREFACE.start_with?(@buffer.byteslice(0, 24))
        raise ConnectionError.new(:protocol_error) # (MAY) send GOAWAY. sending.
      end

      if @buffer.bytesize >= 24
        @buffer.byteshift(24)
        settings(@local_settings)
        @state = :waiting_settings
      end
    end
  end
end
