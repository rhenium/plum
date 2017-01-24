require_relative "../../utils"

class HPACKContextTest < Test::Unit::TestCase
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

  def test_search_static
    context = new_context
    i1 = context.search(":method", "POST")
    assert_equal(3, i1)
    i2 = context.search_half(":method")
    assert_equal(2, i2)
  end

  def test_search_dynamic
    context = new_context
    context.store("あああ", "abc")
    context.store("あああ", "いい")
    i1 = context.search("あああ", "abc")
    assert_equal(63, i1)
    i2 = context.search("あああ", "AAA")
    assert_equal(nil, i2)
    i3 = context.search_half("あああ")
    assert_equal(62, i3)
  end

  private
  def new_context(limit = 1 << 31)
    klass = Class.new {
      include Plum::HPACK::Context
      public(*Plum::HPACK::Context.private_instance_methods)
    }
    klass.new(limit)
  end
end
