# frozen_string_literal: true

require "active_support/core_ext/object/blank"
require "active_support/core_ext/object/deep_dup"
require "active_support/core_ext/hash/indifferent_access"
require "active_support/hash_with_indifferent_access"
# Pure Ruby, no Active Admin boot required - `visible_filters` resolves `:if` / `:unless` with it.
require "active_admin/view_helpers/method_or_proc_helper"
require "active_admin_filter_extensions/data_access"
require "active_admin_filter_extensions/filter_options"
require "active_admin_filter_extensions/search_keys"
require "active_admin_filter_extensions/required_filters"
require "active_admin_filter_extensions/filter_defaults"
require "active_admin_filter_extensions/policies"

# `DataAccess` only needs `params`, `active_admin_config` and something that answers `ransack`.
# That lets the unit suite run without booting Active Admin or Rails; the integration suite in
# spec/integration exercises the real thing.
class FakeChain
  attr_reader :ransacked_with

  def ransack(params)
    @ransacked_with = params
    self
  end

  def result
    self
  end
end

class FakeController
  # The resource settings the policy layer reads unconditionally in a real install.
  Config = Struct.new(:filters) do
    def require_any_filter_notice = nil
    def default_filters_notice = nil
  end

  def self.before_action(*); end # the guard registers one; FakeController has no chain
  def performed? = false

  attr_reader :params, :active_admin_config

  # Deriving a search key means building a Formtastic input, which needs Rails. What the input
  # would answer is supplied here instead, so these examples cover the step above derivation -
  # splitting a value across the keys - while spec/integration covers the derivation itself.
  def initialize(params: {}, filters: {}, search_keys: {})
    @params = ActiveSupport::HashWithIndifferentAccess.new(params)
    @active_admin_config = Config.new(filters)
    @search_keys = search_keys
  end

  # Plain override: FilterDefaults is included, so the class wins.
  def filter_search_keys(attribute, _options)
    @search_keys.fetch(attribute) { [attribute.to_s] }
  end

  prepend ActiveAdminFilterExtensions::DataAccess
  include ActiveAdminFilterExtensions::Policies::Controller
  include ActiveAdminFilterExtensions::FilterOptions
  include ActiveAdminFilterExtensions::SearchKeys
  include ActiveAdminFilterExtensions::RequiredFilters
  include ActiveAdminFilterExtensions::FilterDefaults
end

RSpec.configure do |config|
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }
end
