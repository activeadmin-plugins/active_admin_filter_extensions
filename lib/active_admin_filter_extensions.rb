# frozen_string_literal: true

require "activeadmin"
require "active_support/core_ext/object/deep_dup"
require "active_admin_filter_extensions/version"

# The violation messages live in plain i18n - config/locales/en.yml here, overridable by the
# application's own locale files under the same keys.
I18n.load_path += Dir[File.expand_path("../config/locales/*.yml", __dir__)]
require "active_admin_filter_extensions/data_access"
require "active_admin_filter_extensions/filter_options"
require "active_admin_filter_extensions/search_keys"
require "active_admin_filter_extensions/required_filters"
require "active_admin_filter_extensions/filter_defaults"
require "active_admin_filter_extensions/filters_form"
require "active_admin_filter_extensions/redirect"
require "active_admin_filter_extensions/policies"
require "active_admin_filter_extensions/notice"

module ActiveAdminFilterExtensions
  class << self
    # Where a filters notice goes when the resource does not say. Active Admin writes action
    # results to :notice, and an app whose layout renders its own key for "why this page is
    # cut down" would otherwise repeat `flash_key:` on every index that declares a notice:
    #
    #   ActiveAdminFilterExtensions.notice_flash_key = :notice_message
    #
    # Read when the notice is written, not when the resource is registered, so initializer
    # order does not decide it.
    attr_writer :notice_flash_key

    def notice_flash_key
      @notice_flash_key ||= :notice
    end
  end
end

# `add_filter` stores whatever options it is given without a whitelist, so `default:` needs no
# registration of its own.
ActiveAdmin.before_load do |_app|
  # Prepended, because it replaces Active Admin's own #apply_filtering.
  ActiveAdmin::ResourceController.prepend ActiveAdminFilterExtensions::DataAccess
  # Included, because it only adds - and a resource overriding one of its seams in a
  # `controller do` block should win, which is what including gives.
  ActiveAdmin::ResourceController.include ActiveAdminFilterExtensions::FilterOptions
  ActiveAdmin::ResourceController.include ActiveAdminFilterExtensions::SearchKeys
  ActiveAdmin::ResourceController.include ActiveAdminFilterExtensions::RequiredFilters
  ActiveAdmin::ResourceController.include ActiveAdminFilterExtensions::FilterDefaults
  ActiveAdmin::ResourceController.helper_method :filtering_params, :applied_filter_params,
                                                :filter_default_values, :visible_filters

  ActiveAdmin::Resource.prepend ActiveAdminFilterExtensions::ResourceExtension
  ActiveAdmin::ResourceDSL.include ActiveAdminFilterExtensions::Policies::ResourcePolicyDSL
  ActiveAdmin::Resource.include ActiveAdminFilterExtensions::Policies::ResourcePolicySettings
  ActiveAdmin::ResourceDSL.include ActiveAdminFilterExtensions::Notice
  ActiveAdmin::Resource.include ActiveAdminFilterExtensions::NoticeResource
  # Policies before the redirect: a sanitized or reset value must be what the redirect
  # decision - and therefore the URL - is computed from.
  ActiveAdmin::ResourceController.include ActiveAdminFilterExtensions::Policies::Controller
  ActiveAdmin::ResourceController.include ActiveAdminFilterExtensions::Redirect
  ActiveAdmin::Filters::ViewHelper.prepend ActiveAdminFilterExtensions::ViewHelper
  ActiveAdmin::Filters::ActiveSidebar.prepend ActiveAdminFilterExtensions::ActiveSidebar
end
