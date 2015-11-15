# -*- frozen-string-literal: true -*-
using Plum::BinaryString
module Plum
  class ServerConnection < Connection
    def initialize(writer, local_settings = {})
      super(writer, local_settings)

      @state = :waiting_preface
    end

    # Reserves a new stream to server push.
    # @param args [Hash] The argument to pass to Stram.new.
    def reserve_stream(**args)
      next_id = @max_stream_ids[0] + 2
      stream = stream(next_id)
      stream.set_state(:reserved_local)
      stream.update_dependency(**args)
      stream
    end

    private
    def consume_buffer
      if @state == :waiting_preface
        negotiate!
      end

      super
    end

    def negotiate!
      unless CLIENT_CONNECTION_PREFACE.start_with?(@buffer.byteslice(0, 24))
        raise RemoteConnectionError.new(:protocol_error) # (MAY) send GOAWAY. sending.
      end

      if @buffer.bytesize >= 24
        @buffer.byteshift(24)
        settings(@local_settings)
        @state = :waiting_settings
      end
    end
  end
end
