using Plum::BinaryString

module Plum
  class HTTPSConnection < Connection
    def initialize(io, local_settings = {})
      super
    end

    private
    def negotiate!
      return if @buffer.empty?

      if CLIENT_CONNECTION_PREFACE.start_with?(@buffer.byteslice(0, 24))
        if @buffer.bytesize >= 24
          @buffer.byteshift(24)
          @state = :waiting_settings
          settings(@local_settings)
        end
      else
        raise ConnectionError.new(:protocol_error) # (MAY) send GOAWAY. sending.
      end
    end
  end
end
