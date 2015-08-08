require "timeout"

module ServerUtils
  def open_server_connection(scheme = :https)
    io = StringIO.new
    @_con = (scheme == :https ? HTTPSConnection : HTTPConnection).new(io)
    @_con << Connection::CLIENT_CONNECTION_PREFACE
    @_con << Frame.new(type: :settings, stream_id: 0).assemble
    if block_given?
      yield @_con
    else
      @_con
    end
  end

  def open_new_stream(arg1 = nil, **kwargs)
    if arg1.is_a?(Connection)
      con = arg1
    else
      con = open_server_connection
    end

    @_stream = con.instance_eval {
      new_stream((con.streams.keys.last||0/2)*2+1, **kwargs)
    }
    if block_given?
      yield @_stream
    else
      @_stream
    end
  end

  def sent_frames(con = nil)
    resp = (con || @_con).io.string.dup
    frames = []
    while f = Frame.parse!(resp)
      frames << f
    end
    frames
  end
end

class Minitest::Test
  include ServerUtils
end
