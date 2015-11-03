# -*- frozen-string-literal: true -*-
using Plum::BinaryString
module Plum
  class ClientConnection < Connection
    def initialize(writer, local_settings = {})
      super(writer, local_settings)

      writer.call(CLIENT_CONNECTION_PREFACE)
      settings(local_settings)
      @state = :waiting_settings
    end

    def open_stream(**args)
      next_id = @max_odd_stream_id > 0 ? @max_odd_stream_id + 2 : 1
      stream = new_stream(next_id, state: :open, **args)
      stream
    end
  end
end
