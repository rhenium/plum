using Plum::BinaryString

module Plum
  module StreamHelper
    # Responds to HTTP request.
    #
    # @param headers [Hash<String, String>] The response headers.
    # @param body [String, IO] The response body.
    def respond(headers, body = nil, end_stream: true) # TODO: priority, padding
      if body
        send_headers(headers, end_stream: false)
        send_data(body, end_stream: end_stream)
      else
        send_headers(headers, end_stream: end_stream)
      end
    end

    # Reserves a stream to server push. Sends PUSH_STREAM and create new stream.
    #
    # @param headers [Hash<String, String>] The *request* headers. It must contain all of them: ':authority', ':method', ':scheme' and ':path'.
    # @return [Stream] The stream to send push response.
    def promise(headers)
      stream = @connection.reserve_stream(weight: self.weight + 1, parent: self)
      encoded = @connection.hpack_encoder.encode(headers)
      original = Frame.push_promise(id, stream.id, encoded, :end_headers)
      original.split_headers(@connection.remote_settings[:max_frame_size]).each do |frame|
        send frame
      end
      stream
    end

    private
    def send_headers(headers, end_stream:)
      max = @connection.remote_settings[:max_frame_size]
      encoded = @connection.hpack_encoder.encode(headers)
      original_frame = Frame.headers(id, encoded, :end_headers, (end_stream && :end_stream))
      original_frame.split_headers(max).each do |frame|
        send frame
      end
      @state = :half_closed_local if end_stream
    end

    def send_data(data, end_stream: true)
      max = @connection.remote_settings[:max_frame_size]
      if data.is_a?(IO)
        while !data.eof? && fragment = data.readpartial(max)
          send Frame.data(id, fragment, (end_stream && data.eof? && :end_stream))
        end
      else
        original = Frame.data(id, data, (end_stream && :end_stream))
        original.split_data(max).each do |frame|
          send frame
        end
      end
      @state = :half_closed_local if end_stream
    end
  end
end
