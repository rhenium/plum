# -*- frozen-string-literal: true -*-
lib = File.expand_path("../lib", __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require "plum/version"

Gem::Specification.new do |spec|
  spec.name          = "plum"
  spec.version       = Plum::VERSION
  spec.authors       = ["rhenium"]
  spec.email         = ["k@rhe.jp"]

  spec.summary       = %q{A minimal implementation of HTTP/2 server.}
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/rhenium/plum"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x00")
  spec.executables   = spec.files.grep(%r{^bin/[^.]}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^test/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.10"
  spec.add_development_dependency "http_parser.rb"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "yard"
  spec.add_development_dependency "minitest", "~> 5.7.0"
  spec.add_development_dependency "simplecov"
  spec.add_development_dependency "codeclimate-test-reporter"
  spec.add_development_dependency "guard"
  spec.add_development_dependency "guard-minitest"
end
