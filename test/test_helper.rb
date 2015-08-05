LISTEN_PORT = ENV["PLUM_LISTEN_PORT"] || 40444

unless ENV["SKIP_COVERAGE"]
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
end

require "minitest"
require "minitest/unit"
require "minitest/autorun"
require "minitest/pride"
require "plum"
include Plum

Dir.glob(File.expand_path("../utils/*.rb", __FILE__)).each do |file|
  require file
end
