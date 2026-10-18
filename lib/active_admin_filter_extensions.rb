# frozen_string_literal: true

require "activeadmin"
require "active_admin_filter_extensions/version"
require "active_admin_filter_extensions/data_access"
require "active_admin_filter_extensions/filter_options"
require "active_admin_filter_extensions/search_keys"
require "active_admin_filter_extensions/filter_defaults"
require "active_admin_filter_extensions/filters_form"

module ActiveAdminFilterExtensions
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
  ActiveAdmin::ResourceController.include ActiveAdminFilterExtensions::FilterDefaults
  ActiveAdmin::ResourceController.helper_method :filtering_params, :filter_default_values, :visible_filters

  ActiveAdmin::Resource.prepend ActiveAdminFilterExtensions::ResourceExtension
  ActiveAdmin::Filters::ViewHelper.prepend ActiveAdminFilterExtensions::ViewHelper
  ActiveAdmin::Filters::ActiveSidebar.prepend ActiveAdminFilterExtensions::ActiveSidebar
end
