# frozen-string-literal: true

guard :minitest, env: { "SKIP_COVERAGE" => true } do
  # with Minitest::Unit
  watch(%r{^test/(.*)\/?test_(.*)\.rb$})
  watch(%r{^lib/(.*/)?([^/]+)\.rb$})     {|m| ["test/#{m[1]}test_#{m[2]}.rb", "test/#{m[1]}#{m[2]}"] }
  watch(%r{^test/test_helper\.rb$})      { "test" }
  watch(%r{^test/utils/.*\.rb})          { "test" }
end
