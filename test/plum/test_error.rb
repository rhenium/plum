require_relative "../utils"

class ErrorTest < Test::Unit::TestCase
  def test_http_error_http2_error_code
    test = -> klass {
      e = klass.new(:cancel)
      assert_equal(0x08, e.http2_error_code)
    }

    test.call HTTPError
  end
end
