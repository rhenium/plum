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

require "timeout"
require "minitest"
require "minitest/unit"
require "minitest/autorun"
require "minitest/pride"
require "plum"
include Plum

Dir.glob(File.expand_path("../utils/*.rb", __FILE__)).each do |file|
  require file
end

LISTEN_PORT = ENV["PLUM_LISTEN_PORT"] || 40444
TLS_CERT = OpenSSL::X509::Certificate.new File.read(File.expand_path("../server.crt", __FILE__))
TLS_KEY = OpenSSL::PKey::RSA.new File.read(File.expand_path("../server.key", __FILE__))
ExampleError = Class.new(RuntimeError)
