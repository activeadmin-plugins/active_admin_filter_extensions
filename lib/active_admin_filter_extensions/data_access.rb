# frozen_string_literal: true

module ActiveAdminFilterExtensions
  # The single method this gem replaces: Active Admin searches the collection on `params[:q]`
  # read directly, and it searches #filtering_params instead. Everything that method means is
  # in FilterDefaults.
  module DataAccess
    protected

    def apply_filtering(chain)
      @search = chain.ransack(filtering_params, **filter_ransack_options)
      # An :empty policy keeps the request intact - the form still shows what the admin
      # typed - and blanks the collection instead.
      return @search.result.none if filter_policy_render_empty?

      @search.result
    end
  end
end
