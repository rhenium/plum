module CustomAssertions
  def assert_http_error(klass, type, &blk)
    begin
      blk.call
    rescue klass => e
      assert_equal(type, e.http2_error_type)
    else
      flunk "#{klass.name} type: #{type} expected but nothing was raised."
    end
  end

  def assert_connection_error(type, &blk)
    assert_http_error(Plum::ConnectionError, type, &blk)
  end

  def assert_stream_error(type, &blk)
    assert_http_error(Plum::StreamError, type, &blk)
  end

  def refute_raises(&blk)
    begin
      blk.call
    rescue
      a = $!
    else
      a = nil
    end
    assert(!a, "No exceptions expected but raised: #{a}:\n#{a && a.backtrace.join("\n")}")
  end
end

class Minitest::Test
  include CustomAssertions
end
