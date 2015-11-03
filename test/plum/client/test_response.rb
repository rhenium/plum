require "test_helper"

using Plum::BinaryString
class ResponseTest < Minitest::Test
  def test_finished
    resp = Response.new
    assert_equal(false, resp.finished?)
    resp._finish
    assert_equal(true, resp.finished?)
  end

  def test_status
    resp = Response.new
    resp._headers([
      [":status", "200"]
    ])
    assert_equal("200", resp.status)
  end

  def test_headers
    resp = Response.new
    resp._headers([
      [":status", "200"],
      ["header", "abc"]
    ])
    assert_equal("abc", resp[:HEADER])
  end

  def test_body
    resp = Response.new
    resp._chunk("a")
    resp._chunk("b")
    resp._finish
    assert_equal("ab", resp.body)
  end

  def test_each_chunk
    resp = Response.new
    res = []
    resp._chunk("a")
    resp._chunk("b")
    resp._finish
    resp.each_chunk { |chunk| res << chunk }
    assert_equal(["a", "b"], res)
  end
end