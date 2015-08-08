module CustomAssertions
  def assert_connection_error(type, &blk)
    assert_http_error(Plum::ConnectionError, type, &blk)
  end

  def assert_stream_error(type, &blk)
    assert_http_error(Plum::StreamError, type, &blk)
  end

  def assert_no_error(stream: nil, connection: nil, &blk)
    Plum::ConnectionError.reset
    Plum::StreamError.reset
    begin
      blk.call
    rescue Plum::HTTPError
    end
    assert_nil(Plum::StreamError.last, "No stream error expected but raised: #{Plum::StreamError.last}")
    assert_nil(Plum::ConnectionError.last, "No connection error expected but raised: #{Plum::ConnectionError.last}")
  end

  private
  def assert_http_error(klass, type, &blk)
    klass.reset
    begin
      blk.call
    rescue klass
    end
    last = klass.last
    assert(last, "#{klass.name} type: #{type} expected but nothing was raised.")
    assert_equal(type, last, "#{klass.name} type: #{type} expected but type: #{last} was raised.")
  end
end
Minitest::Test.__send__(:prepend, CustomAssertions)

module LastErrorExtension
  def initialize(type, message = nil)
    super
    self.class.last = type
  end

  module ClassMethods
    attr_accessor :last
    def reset
      self.last = nil
    end
  end

  def self.prepended(base)
    base.extend(ClassMethods)
    base.reset
  end
end
Plum::ConnectionError.__send__(:prepend, LastErrorExtension)
Plum::StreamError.__send__(:prepend, LastErrorExtension)
