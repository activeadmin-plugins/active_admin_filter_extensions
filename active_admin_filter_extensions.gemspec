# frozen_string_literal: true

require_relative "lib/active_admin_filter_extensions/version"

Gem::Specification.new do |s|
  s.name        = "active_admin_filter_extensions"
  s.version     = ActiveAdminFilterExtensions::VERSION
  s.authors     = ["Igor Fedoronchuk"]
  s.email       = ["fedoronchuk@gmail.com"]
  s.homepage    = "https://github.com/activeadmin-plugins/active_admin_filter_extensions"
  s.license     = "MIT"
  s.summary     = "Default values for Active Admin index filters"
  s.description = "Lets an Active Admin resource declare what its index filters on when opened " \
                  "without filters of its own: filter :state_eq, extensions: { default: 'active' }"

  s.required_ruby_version = ">= 3.3"
  s.add_dependency "activeadmin", ">= 3.5", "< 4"

  s.files         = `git ls-files`.split("\n")
  s.require_paths = ["lib"]

  s.metadata = {
    "homepage_uri" => s.homepage,
    "source_code_uri" => s.homepage,
    "rubygems_mfa_required" => "true"
  }
end
