# frozen-string-literal: true

using Plum::BinaryString

module Plum
  module FlowControl
    attr_reader :send_remaining_window, :recv_remaining_window

    # Sends frame respecting inner-stream flow control.
    # @param frame [Frame] The frame to be sent.
    def send(frame)
      if Frame::Data === frame
        @send_buffer << frame
        if @send_remaining_window < frame.length
          if Stream === self
            connection.callback(:send_deferred, self, frame)
          else
            callback(:send_deferred, self, frame)
          end
        else
          consume_send_buffer
        end
      else
        send_immediately frame
      end
    end

    # Increases receiving window size. Sends WINDOW_UPDATE frame to the peer.
    # @param wsi [Integer] The amount to increase receiving window size. The legal range is 1 to 2^32-1.
    def window_update(wsi)
      @recv_remaining_window += wsi
      sid = (Stream === self) ? self.id : 0
      send_immediately Frame::WindowUpdate.new(sid, wsi)
    end

    protected
    def update_send_initial_window_size(diff)
      @send_remaining_window += diff
      consume_send_buffer

      if Connection === self
        @streams.values.each do |stream|
          stream.update_send_initial_window_size(diff)
        end
      end
    end

    def update_recv_initial_window_size(diff)
      @recv_remaining_window += diff
      if Connection === self
        @streams.values.each do |stream|
          stream.update_recv_initial_window_size(diff)
        end
      end
    end

    private
    def initialize_flow_control(send:, recv:)
      @send_buffer = []
      @send_remaining_window = send
      @recv_remaining_window = recv
    end

    def consume_recv_window(frame)
      if Frame::Data === frame
        @recv_remaining_window -= frame.length
        if @recv_remaining_window < 0
          local_error = (Connection === self) ? RemoteConnectionError : RemoteStreamError
          raise local_error.new(:flow_control_error)
        end
      end
    end

    def consume_send_buffer
      while frame = @send_buffer.first
        break if frame.length > @send_remaining_window
        @send_buffer.shift
        @send_remaining_window -= frame.length
        send_immediately frame
      end
    end

    def receive_window_update(frame)
      if frame.length != 4
        raise Plum::RemoteConnectionError.new(:frame_size_error)
      end

      r_wsi = frame.payload.uint32
      # r = r_wsi >> 31 # currently not used
      wsi = r_wsi # & ~(1 << 31)

      if wsi == 0
        local_error = (Connection === self) ? RemoteConnectionError : RemoteStreamError
        raise local_error.new(:protocol_error)
      end

      if Stream === self
        connection.callback(:window_update, self, wsi)
      else
        callback(:window_update, self, wsi)
      end

      @send_remaining_window += wsi
      consume_send_buffer
    end
  end
end
