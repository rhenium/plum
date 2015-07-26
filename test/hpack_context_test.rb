require "test_helper"

class HPACKContextTest < Minitest::Test
  def test_store
    context = new_context
    context.store("あああ", "いい")
    assert_equal([["あああ", "いい"]], context.dynamic_table)
    assert_equal("あああいい".bytesize + 32, context.size)
  end

  def test_store_eviction
    context = new_context(1)
    context.store("あああ", "いい")
    assert_equal([], context.dynamic_table)
    assert_equal(0, context.size)
  end

  def test_fetch_static
    context = new_context
    assert_equal([":method", "POST"], context.fetch(3))
  end

  def test_fetch_dynamic
    context = new_context
    context.store("あああ", "いい")
    assert_equal(["あああ", "いい"], context.fetch(62))
  end

  def test_fetch_error
    context = new_context
    context.store("あああ", "いい")
    assert_raises(Plum::HPACKError) {
      context.fetch(64)
    }
  end

  private
  def new_context(limit = 1 << 31)
    @c ||= Class.new {
      include Plum::HPACK::Context
      public :initialize, :store, :fetch, :evict
    }
    @c.new(limit)
  end
end