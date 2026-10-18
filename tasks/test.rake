# frozen_string_literal: true

desc "Creates a test rails app for the specs to run against"
task :setup do
  require "rails/version"

  # The template throws the generated Gemfile away, so the app runs under this gem's sprockets
  # bundle with no importmap-rails. Without --skip-javascript, Rails 8.1 writes
  # `stale_when_importmap_changes` into ApplicationController and booting it raises NameError.
  args = %w[
    --skip-spring
    --skip-bootsnap
    --skip-test
    --skip-system-test
    --skip-javascript
    -m spec/support/rails_template.rb
  ].join(" ")

  app_dir = "spec/rails/rails-#{Rails::VERSION::STRING}"
  sh "bundle exec rails new #{app_dir} #{args}"

  # Stamped so rails_helper can refuse an app generated from an older template instead of
  # silently testing against resources the template no longer declares.
  require "digest"
  File.write(File.join(app_dir, ".rails_template_digest"),
             Digest::SHA256.file("spec/support/rails_template.rb").hexdigest)
end
