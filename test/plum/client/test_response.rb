require "test_helper"

using Plum::BinaryString
class ResponseTest < Minitest::Test
  def test_finished
    resp = Response.new(nil)
    resp.send(:set_headers, {})
    assert_equal(false, resp.finished?)
    resp.send(:finish)
    assert_equal(true, resp.finished?)
  end

  def test_fail
    resp = Response.new(nil)
    resp.send(:fail, true)
    assert(resp.failed?, "response must be failed")
  end

  def test_status
    resp = Response.new(nil)
    resp.send(:set_headers,
      ":status" => "200"
    )
    assert_equal("200", resp.status)
  end

  def test_headers
    resp = Response.new(nil)
    resp.send(:set_headers,
      ":status" => "200",
      "header" => "abc"
    )
    assert_equal("abc", resp[:HEADER])
  end

  def test_body
    resp = Response.new(nil)
    resp.send(:set_headers, {})
    resp.send(:add_chunk, "a")
    resp.send(:add_chunk, "b")
    resp.send(:finish)
    assert_equal("ab", resp.body)
  end

  def test_body_not_finished
    resp = Response.new(nil)
    resp.send(:set_headers, {})
    resp.send(:add_chunk, "a")
    resp.send(:add_chunk, "b")
    assert_raises { # TODO
      resp.body
    }
  end

  def test_on_headers_initialize
    called = false
    resp = Response.new(nil) { |r| called = true }
    assert(!called)
    resp.send(:set_headers, { ":status" => 201 })
    assert(called)
  end

  def test_on_headers_explicit
    called = false
    resp = Response.new(nil)
    resp.on_headers { |r| called = true }
    assert(!called)
    resp.send(:set_headers, { ":status" => 201 })
    assert(called)
  end

  def test_on_chunk
    resp = Response.new(nil)
    resp.send(:set_headers, {})
    res = []
    resp.send(:add_chunk, "a")
    resp.send(:add_chunk, "b")
    resp.send(:finish)
    resp.on_chunk { |chunk| res << chunk }
    assert_equal(["a", "b"], res)
    resp.send(:add_chunk, "c")
    assert_equal(["a", "b", "c"], res)
  end

  def test_on_finish
    resp = Response.new(nil)
    resp.send(:set_headers, {})
    ran = false
    resp.on_finish { ran = true }
    resp.send(:finish)
    assert(ran)
    ran = false
    resp.on_finish { ran = true }
    assert(ran)
  end

  # FIXME: test Response#join
end
