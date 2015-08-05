require "test_helper"

class ErrorTest < Minitest::Test
  def test_http_error_http2_error_code
    test = -> klass {
      e = klass.new(:cancel)
      assert_equal(0x08, e.http2_error_code)
    }

    test.call ConnectionError
    test.call StreamError
  end
end
