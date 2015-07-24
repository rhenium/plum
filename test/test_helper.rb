begin
  require "coveralls"
  require "simplecov"
  Coveralls.wear!
  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
    SimpleCov::Formatter::HTMLFormatter,
    Coveralls::SimpleCov::Formatter
  ]
  SimpleCov.start do
    add_filter "test/"
  end
rescue LoadError
end

require "plum"
require "timeout"
require "minitest"
require "minitest/unit"
require "minitest/autorun"
require "minitest/pride"
require "utils"

LISTEN_PORT = ENV["PLUM_LISTEN_PORT"] || 40444
