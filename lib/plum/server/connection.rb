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
      next_id = @max_even_stream_id + 2
      stream = new_stream(next_id, state: :reserved_local, **args)
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
