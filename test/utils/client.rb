require "timeout"

module ServerUtils
  def open_client_connection(scheme = :https)
    io = StringIO.new
    @_ccon = ClientConnection.new(io.method(:write))
    @_ccon << Frame.new(type: :settings, stream_id: 0, flags: [:ack]).assemble
    @_ccon << Frame.new(type: :settings, stream_id: 0).assemble
    if block_given?
      yield @_ccon
    else
      @_ccon
    end
  end
end

class Minitest::Test
  include ServerUtils
end
