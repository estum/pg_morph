require "rake/testtask"
require "rspec/core/rake_task"

RSpec::Core::RakeTask.new(:spec)
task default: :spec

desc 'test pg_morph'
Rake::TestTask.new do |t|
  t.libs << 'spec'
  t.pattern = 'spec/**/*_spec.rb'
  t.verbose = true
end

load File.expand_path("../spec/dummy/Rakefile", __FILE__)
