# frozen-string-literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "yard"

Rake::TestTask.new do |t|
  t.libs << "test" << "lib"
  t.pattern = "test/**/test_*.rb"
end

YARD::Rake::YardocTask.new do |t|
  t.files   = ["lib/**/*.rb"]
end
