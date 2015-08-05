guard :minitest, env: { "SKIP_COVERAGE" => true } do
  # with Minitest::Unit
  watch(%r{^test/(.*)_test\.rb$})
  watch(%r{^test/test_helper\.rb$}) { "test" }
  watch(%r{^test/utils\.rb$}) { "test" }
  watch(%r{^lib/plum.rb$}) { "test" }
  watch(%r{^lib/plum/(.+)\.rb$}) {|m| "test/" + m[1].gsub("/", "_") + "_test.rb" }

  # with Minitest::Spec
  # watch(%r{^spec/(.*)_spec\.rb$})
  # watch(%r{^lib/(.+)\.rb$})         { |m| "spec/#{m[1]}_spec.rb" }
  # watch(%r{^spec/spec_helper\.rb$}) { 'spec' }
end
