# frozen_string_literal: true

# Boots the generated sample app. Only the integration specs need this - the unit specs run
# against a stand-in controller and stay in spec_helper.

$LOAD_PATH.unshift(File.expand_path("support", __dir__))

ENV["BUNDLE_GEMFILE"] = File.expand_path("../Gemfile", __dir__)
require "bundler"
Bundler.setup

ENV["RAILS_ENV"] = "test"
require "rails"
ENV["RAILS"] = Rails.version
ENV["RAILS_ROOT"] = File.expand_path("rails/rails-#{ENV['RAILS']}", __dir__)

unless File.exist?(ENV["RAILS_ROOT"])
  # A generation that dies midway leaves a partial app the File.exist? guard would then skip
  # forever - fail the run instead of limping into it.
  system("rake setup") ||
    abort("rake setup failed - remove #{ENV['RAILS_ROOT']} before retrying")
end

# An app generated from an older template would silently pass against resources the template
# no longer declares - refuse it instead.
require "digest"
template_digest = Digest::SHA256.file(File.expand_path("support/rails_template.rb", __dir__)).hexdigest
stamp = File.join(ENV["RAILS_ROOT"], ".rails_template_digest")
unless File.exist?(stamp) && File.read(stamp).strip == template_digest
  abort "#{ENV['RAILS_ROOT']} was generated from an older rails_template.rb - "         "remove it (git clean -fdx spec/rails) and rerun, rake setup regenerates it"
end

require "active_model"
# Required before Active Admin so that Ransack loads correctly.
require "active_record"
require "action_view"
require "active_admin"
ActiveAdmin.application.load_paths = ["#{ENV['RAILS_ROOT']}/app/admin"]
require "#{ENV['RAILS_ROOT']}/config/environment"

# Specs are about filters, not about signing in.
ActiveAdmin.application.authentication_method = false
ActiveAdmin.application.current_user_method = false

require "rspec/rails"
require "capybara/rails"
require "capybara/rspec"
require "database_cleaner/active_record"
require "capybara_driver"

RSpec.configure do |config|
  config.use_transactional_fixtures = false

  config.before(:suite) do
    ActiveRecord::Migration.maintain_test_schema!
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before { DatabaseCleaner.start }
  config.after { DatabaseCleaner.clean }
end
