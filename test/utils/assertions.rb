module Test::Unit::Assertions
  def assert_connection_error(type, &blk)
    assert_http_error(Plum::RemoteConnectionError, type, &blk)
  end

  def assert_stream_error(type, &blk)
    assert_http_error(Plum::RemoteStreamError, type, &blk)
  end

  def assert_no_error(stream: nil, connection: nil, &blk)
    Plum::RemoteConnectionError.reset
    Plum::RemoteStreamError.reset
    begin
      blk.call
    rescue Plum::RemoteHTTPError
    end
    assert_nil(Plum::RemoteStreamError.last, "No stream error expected but raised: #{Plum::RemoteStreamError.last}")
    assert_nil(Plum::RemoteConnectionError.last, "No connection error expected but raised: #{Plum::RemoteConnectionError.last}")
  end

  def assert_frame(frame, **args)
    args.each do |name, value|
      assert_equal(value, frame.__send__(name))
    end
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
Plum::RemoteConnectionError.__send__(:prepend, LastErrorExtension)
Plum::RemoteStreamError.__send__(:prepend, LastErrorExtension)
