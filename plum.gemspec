Gem::Specification.new do |spec|
  spec.name          = "plum"
  spec.version       = ENV["VERSION"]
  spec.authors       = ["Kazuki Yamaguchi"]
  spec.email         = ["k@rhe.jp"]

  spec.summary       = "An HTTP/2 Library for Ruby"
  spec.description   = spec.summary
  spec.homepage      = "https://github.com/rhenium/plum"
  spec.license       = "MIT"

  spec.files         = Dir["bin/plum", "lib/**/*.rb", "*.md", "LICENSE"]
  spec.executables   = spec.files.grep(%r{^bin/[^.]}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  spec.add_dependency "openssl", "~> 2.0"
  spec.add_development_dependency "test-unit", "~> 3.0"
  spec.add_development_dependency "http_parser.rb"
  spec.add_development_dependency "rack"
end
