# frozen_string_literal: true

module ActiveAdminFilterExtensions
  # Stable hooks for page objects, so specs need not select on Active Admin's CSS classes.
  FORM_OPTIONS = { html: { "data-filter-extensions-form" => "" } }.freeze

  # The filters sidebar hands the form the filters that `:if` and `:unless` allow, so the same
  # set is rendered and consulted for defaults, and the conditions are resolved once.
  module ResourceExtension
    private

    def filters_sidebar_section
      ActiveAdmin::SidebarSection.new :filters, only: :index, if: -> { active_admin_config.filters.any? } do
        # Passed positionally rather than splatted: the section is shown when the resource has
        # any filter at all, and `**{}` would drop the argument entirely once `:if` and
        # `:unless` have denied every one of them.
        active_admin_filters_form_for assigns[:search], visible_filters, FORM_OPTIONS
      end
    end
  end

  # Active Admin 4's sidebar: the section title is rendered inside the block, as
  # `h3.filters-form-title`, and the Current Filters panel is a section of its own.
  module ResourceExtensionV4
    private

    def filters_sidebar_section
      name = :filters
      ActiveAdmin::SidebarSection.new name, only: :index, if: -> { active_admin_config.filters.any? } do
        title = I18n.t("active_admin.sidebars.#{name}", default: name.to_s.titlecase)
        h3 title, class: "filters-form-title", "data-filter-extensions-title" => ""
        active_admin_filters_form_for assigns[:search], visible_filters, FORM_OPTIONS
      end
    end

    # Gated on `params[:q]` like ActiveSidebar below; only its condition is widened.
    def active_search_sidebar_section
      section = super
      shown = section.options[:if]
      section.options[:if] = lambda {
        instance_exec(&shown) ||
          (active_admin_config.current_filters_enabled? && filter_default_values.present?)
      }
      section
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
      super(search, filters.transform_values { |opts| FilterOptions.input_options(opts) }, options)
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
