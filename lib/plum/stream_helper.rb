using Plum::BinaryString

module Plum
  module StreamHelper
    # Increases receiving window size. Sends WINDOW_UPDATE frame to the peer.
    #
    # @param wsi [Integer] The amount to increase receiving window size. The legal range is 1 to 2^32-1.
    def window_update(wsi)
      @recv_remaining_window += wsi
      payload = "".push_uint32(wsi & ~(1 << 31))
      send Frame.new(type: :window_update, stream_id: id, payload: payload)
    end

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
      payload = "".force_encoding(Encoding::BINARY)
      payload.push_uint32((0 << 31 | stream.id))
      payload.push(@connection.hpack_encoder.encode(headers))

      original = Frame.new(type: :push_promise,
                           flags: [:end_headers],
                           stream_id: id,
                           payload: payload)
      original.split_headers(@connection.remote_settings[:max_frame_size]).each do |frame|
        send frame
      end
      stream
    end

    private
    def send_headers(headers, end_stream:)
      max = @connection.remote_settings[:max_frame_size]
      encoded = @connection.hpack_encoder.encode(headers)
      original_frame = Frame.new(type: :headers,
                                 flags: [:end_headers, end_stream ? :end_stream : nil].compact,
                                 stream_id: id,
                                 payload: encoded)
      original_frame.split_headers(max).each do |frame|
        send frame
      end
      @state = :half_closed_local if end_stream
    end

    def send_data(data, end_stream: true)
      max = @connection.remote_settings[:max_frame_size]
      if data.is_a?(IO)
        while !data.eof? && fragment = data.readpartial(max)
          send Frame.new(type: :data,
                         stream_id: id,
                         flags: (end_stream && data.eof? && [:end_stream]),
                         payload: fragment)
        end
      else
        original = Frame.new(type: :data,
                             stream_id: id,
                             flags: (end_stream && [:end_stream]),
                             payload: data.to_s)
        original.split_data(max).each do |frame|
          send frame
        end
      end
      @state = :half_closed_local if end_stream
    end
  end
end