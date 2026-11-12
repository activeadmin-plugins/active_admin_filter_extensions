# frozen_string_literal: true

source "https://rubygems.org"

gemspec

default_rails_version = "8.0.0"
default_activeadmin_version = "3.5.0"

gem "rails", "~> #{ENV['RAILS'] || default_rails_version}"
activeadmin_version = ENV["AA"] || default_activeadmin_version
gem "activeadmin", "~> #{activeadmin_version}"
# Active Admin 4 serves its assets through propshaft and an import map, Active Admin 3 through
# Sprockets and Sass.
if Gem::Version.new(activeadmin_version) >= Gem::Version.new("4.0.0.beta1")
  gem "importmap-rails"
  gem "propshaft"
else
  gem "sprockets-rails"
  gem "sass-rails"
end

group :test do
  gem "capybara"
  gem "cuprite"
  gem "database_cleaner-active_record"
  gem "rspec-rails"
  gem "sqlite3", "~> 2.0"
  gem "webrick", require: false
end
