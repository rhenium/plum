begin
  require "simplecov"
  require "codeclimate-test-reporter"
  SimpleCov.formatter = SimpleCov::Formatter::MultiFormatter[
    SimpleCov::Formatter::HTMLFormatter,
    CodeClimate::TestReporter::Formatter
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

include Plum
