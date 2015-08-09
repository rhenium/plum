require "test_helper"

using BinaryString
class EventEmitterTest < Minitest::Test
  def test_simple
    ret = nil
    emitter = new_emitter
    emitter.on(:event) {|arg| ret = arg }
    emitter.callback(:event, 123)
    assert_equal(123, ret)
  end

  def test_multiple
    ret1 = nil; ret2 = nil
    emitter = new_emitter
    emitter.on(:event) {|arg| ret1 = arg }
    emitter.on(:event) {|arg| ret2 = arg }
    emitter.callback(:event, 123)
    assert_equal(123, ret1)
    assert_equal(123, ret2)
  end

  private
  def new_emitter
    klass = Class.new {
      include EventEmitter
      public *EventEmitter.private_instance_methods
    }
    klass.new
  end
end
