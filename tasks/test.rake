# frozen_string_literal: true

desc "Creates a test rails app for the specs to run against"
task :setup do
  require "rails/version"

  # The template throws the generated Gemfile away, so the app runs under this gem's bundle,
  # which has no importmap-rails on Active Admin 3. Without --skip-javascript, Rails 8.1 writes
  # `stale_when_importmap_changes` into ApplicationController and booting it raises NameError.
  args = %w[
    --skip-spring
    --skip-bootsnap
    --skip-test
    --skip-system-test
    --skip-javascript
    -m spec/support/rails_template.rb
  ].join(" ")

  # Plain `rake setup` has not activated the bundle, and Gem.loaded_specs needs it.
  require "bundler/setup"
  # One app per Active Admin major: its installer writes different assets and initializers.
  aa_major = Gem.loaded_specs["activeadmin"].version.segments.first
  app_dir = "spec/rails/rails-#{Rails::VERSION::STRING}-aa#{aa_major}"
  # From scratch, always: `rails new` git-inits the app, so a nested repo survives
  # `git clean -fdx` and the generator would then write into the surviving tree - leaving a
  # stale resource behind a freshly stamped digest, which is a green the stamp exists to deny.
  require "fileutils"
  FileUtils.rm_rf(app_dir)
  sh "bundle exec rails new #{app_dir} #{args}"

  # Stamped so rails_helper can refuse an app generated from an older template instead of
  # silently testing against resources the template no longer declares.
  require "digest"
  File.write(File.join(app_dir, ".rails_template_digest"),
             Digest::SHA256.file("spec/support/rails_template.rb").hexdigest)
end
