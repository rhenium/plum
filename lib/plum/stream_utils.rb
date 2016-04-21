# -*- frozen-string-literal: true -*-
using Plum::BinaryString

module Plum
  module StreamUtils
    # Reserves a stream to server push. Sends PUSH_PROMISE and create new stream.
    # @param headers [Enumerable<String, String>] The *request* headers. It must contain all of them: ':authority', ':method', ':scheme' and ':path'.
    # @return [Stream] The stream to send push response.
    def promise(headers)
      stream = @connection.reserve_stream(weight: self.weight + 1, parent: self)
      encoded = @connection.hpack_encoder.encode(headers)
      frame = Frame.push_promise(id, stream.id, encoded, end_headers: true)
      send frame
      stream
    end

    # Sends response headers. If the encoded frame is larger than MAX_FRAME_SIZE, the headers will be splitted into HEADERS frame and CONTINUATION frame(s).
    # @param headers [Enumerable<String, String>] The response headers.
    # @param end_stream [Boolean] Set END_STREAM flag or not.
    def send_headers(headers, end_stream:)
      encoded = @connection.hpack_encoder.encode(headers)
      frame = Frame.headers(id, encoded, end_headers: true, end_stream: end_stream)
      send frame
      @state = :half_closed_local if end_stream
    end

    # Sends DATA frame. If the data is larger than MAX_FRAME_SIZE, DATA frame will be splitted.
    # @param data [String, IO] The data to send.
    # @param end_stream [Boolean] Set END_STREAM flag or not.
    def send_data(data = "", end_stream: true)
      max = @connection.remote_settings[:max_frame_size]
      if data.is_a?(IO)
        until data.eof?
          fragment = data.readpartial(max)
          send Frame.data(id, fragment, end_stream: end_stream && data.eof?)
        end
      else
        send Frame.data(id, data, end_stream: end_stream)
      end
      @state = :half_closed_local if end_stream
    end
  end
end
