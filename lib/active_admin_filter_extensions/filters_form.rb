# frozen_string_literal: true

module ActiveAdminFilterExtensions
  # The filters sidebar hands the form the filters that `:if` and `:unless` allow, so the same
  # set is rendered and consulted for defaults, and the conditions are resolved once.
  module ResourceExtension
    private

    def filters_sidebar_section
      ActiveAdmin::SidebarSection.new :filters, only: :index, if: -> { active_admin_config.filters.any? } do
        # Passed positionally rather than splatted: the section is shown when the resource has
        # any filter at all, and `**{}` would drop the argument entirely once `:if` and
        # `:unless` have denied every one of them.
        active_admin_filters_form_for assigns[:search], visible_filters
      end
    end
  end

  # The form renders what it is handed: `:if` and `:unless` were already resolved by
  # #visible_filters, and the policy keys - merged flat into these options by
  # #merge_filter_extensions - are not Formtastic's business. required: in particular is also a
  # Formtastic option: leaked, it would mark the sidebar input HTML-required.
  #
  # The options are cleaned before `super` sees them rather than editing the loop inside the
  # method, so that this gem carries no copy of a method body that belongs to Active Admin.
  module ViewHelper
    def active_admin_filters_form_for(search, filters, options = {})
      super(search, filters.transform_values { |opts| opts.except(*FilterOptions::NOT_FOR_INPUT, *FilterOptions::EXTENSION_KEYS) }, options)
    end
  end

  # The Current Filters panel is gated on `params[:q]`, which stays empty when the values came
  # from `filter ..., default:` rather than from the request.
  module ActiveSidebar
    protected

    def sidebar_options
      {
        only: :index,
        if: -> {
          active_admin_config.current_filters_enabled? &&
            (params[:q] || params[:scope] || filter_default_values.present?)
        }
      }
    end
  end
end
