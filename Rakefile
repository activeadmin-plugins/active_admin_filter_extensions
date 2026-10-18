# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"

Dir["tasks/**/*.rake"].each { |task| load task }

RSpec::Core::RakeTask.new(:unit) do |t|
  t.pattern = "spec/*_spec.rb"
end

desc "Run the integration suite against the generated sample app"
task :integration do
  sh "bundle exec rspec spec/integration"
end

task spec: %i[unit integration]
task default: :spec
