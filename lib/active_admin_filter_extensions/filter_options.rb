# frozen_string_literal: true

module ActiveAdminFilterExtensions
  # The boundary where Active Admin's filter options meet this gem's: which filters are
  # visible on this request, and the one `extensions:` container everything of the gem's lives
  # under - so the form never has to know the keys one by one and their names can never
  # collide with Formtastic's own (required:, most notably).
  module FilterOptions
    # Read here and never handed to an input: `:policy` holds everything of this gem's, and
    # `:if` / `:unless` are Active Admin's but are resolved by #visible_filters before the
    # form is given anything.
    NOT_FOR_INPUT = %i[extensions if unless].freeze

    protected

    # The filters of this resource that `:if` and `:unless` allow, which is both the set the
    # filters form renders and the set that can impose a default - a filter that is not
    # rendered does not filter the collection behind the admin's back.
    #
    # @return [Hash] filter attribute => filter options
    def visible_filters
      @visible_filters ||= active_admin_config.filters.reject do |_attribute, options|
        (options.key?(:if) && !::MethodOrProcHelper.render_in_context(self, options[:if])) ||
          (options.key?(:unless) && ::MethodOrProcHelper.render_in_context(self, options[:unless]))
      end.to_h { |attribute, options| [attribute, merge_filter_extensions(attribute, options)] }
    end

    # Everything of the gem's lives under ONE filter option - extensions: - so the form never
    # has to know the keys one by one and their names can never collide with Formtastic's own.
    # Internally the sub-hash merges flat.
    def merge_filter_extensions(_attribute, options)
      options.merge(options[:extensions] || {})
    end
  end
end
