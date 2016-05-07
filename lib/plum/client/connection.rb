# frozen-string-literal: true

using Plum::BinaryString
module Plum
  class ClientConnection < Connection
    def initialize(writer, local_settings = {})
      super(writer, local_settings)

      writer.call(CLIENT_CONNECTION_PREFACE)
      settings(local_settings)
      @state = :waiting_settings
    end

    # Create a new stream for HTTP request.
    def open_stream
      next_id = @max_stream_ids[1] + 2
      stream(next_id)
    end
  end
end
