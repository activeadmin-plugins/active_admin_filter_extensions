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
          (active_admin_config.current_filters_enabled? && filtering_params.present?)
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
      filters = filters.to_h do |attribute, opts|
        # Asked of the controller only for a none: filter - the helper exists on resource pages,
        # and this method is also mixed into views that are not one.
        opts = none_filter_form_options(attribute, opts, search, self) if opts[:none]
        [attribute, FilterOptions.input_options(opts)]
      end
      super(search, filters, options)
    end
  end

  # Current Filters lists the search's top-level conditions. A None option is a `_null` there,
  # reading "is null 1" - and beside other values it is in an OR grouping, which is not listed
  # at all. Prepended to ActiveAdmin::Filters::Active, the one class both versions list from.
  module CurrentFilters
    def initialize(resource, search)
      super
      labels = search.instance_variable_get(NoneOption::LABELS)
      return if labels.blank?

      filters.each { |filter| name_none_filter(filter, labels[filter.condition.key]) }
      search.base.groupings.each do |grouping|
        null = grouping.conditions.find { |condition| labels.key?(condition.key) }
        next unless null

        (grouping.conditions - [null]).each do |condition|
          filters << name_none_filter(build_filters([condition]).first, labels[null.key])
        end
      end
    end

    private

    def name_none_filter(filter, label)
      return filter unless label

      filter.extend(NoneActiveFilter).none_label = label
      filter
    end
  end

  # One Current Filters entry of a None option: "Account equals None" for the `_null` alone,
  # "Status in None and draft" for the values chosen beside it.
  module NoneActiveFilter
    attr_writer :none_label

    def values
      [@none_label] + (none_alone? ? [] : super.to_a)
    end

    def predicate_name
      none_alone? ? ::Ransack::Translate.predicate("eq") : super
    end

    private

    def none_alone?
      condition.predicate.name == "null"
    end
  end

  # The Current Filters panel is gated on `params[:q]`, which stays empty when the values came
  # from `filter ..., default:` rather than from the request. The effective filters decide, not
  # the configured defaults: a blank submit suppresses the defaults and filters nothing.
  module ActiveSidebar
    protected

    def sidebar_options
      {
        only: :index,
        if: -> {
          active_admin_config.current_filters_enabled? &&
            (params[:q] || params[:scope] || filtering_params.present?)
        }
      }
    end
  end
end
