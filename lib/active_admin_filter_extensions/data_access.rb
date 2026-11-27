# frozen_string_literal: true

module ActiveAdminFilterExtensions
  # The single method this gem replaces: Active Admin searches the collection on `params[:q]`
  # read directly, and it searches #filtering_params instead. Everything that method means is
  # in FilterDefaults. A None option's sentinel becomes its `_null` condition here and no
  # earlier - see NoneOption.
  module DataAccess
    protected

    def apply_filtering(chain)
      @search = chain.ransack(none_filter_search_params(filtering_params), **filter_ransack_options)
      label_none_filters(@search)
      # An :empty policy keeps the request intact - the form still shows what the admin
      # typed - and blanks the collection instead.
      return @search.result.none if filter_policy_render_empty?

      @search.result
    end
  end
end
