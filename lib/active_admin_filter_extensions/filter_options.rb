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
    EXTENSION_KEYS = %i[default required with sanitize validate on_invalid max_range min message].freeze
    # required: and min: are documented Formtastic input options in their own right. The gem
    # answers to them only INSIDE extensions:, so flat they are the host's: no stray-key raise,
    # no policy, straight through to the input.
    HOST_INPUT_KEYS = %i[required min].freeze
    STRAY_KEYS = (EXTENSION_KEYS - HOST_INPUT_KEYS).freeze
    # Where #merge_filter_extensions parks the host's own required:/min:, out of reach of the
    # gem's flat reads until #input_options hands them back to the input.
    HOST_INPUT_OPTIONS = :extensions_host_input_options

    # What the form may see: the gem's container and conditions out, the keys the container
    # itself declared out, and the host's own options back in.
    def self.input_options(options)
      options.except(*NOT_FOR_INPUT, HOST_INPUT_OPTIONS,
                     *(options[:extensions] || {}).keys.map(&:to_sym))
             .merge(options[HOST_INPUT_OPTIONS] || {})
    end

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

    # Everything of the gem's lives under ONE filter option - extensions: - so the form never has
    # to know the keys one by one and their names can never collide with Formtastic's own
    # (required:, most notably). Internally the sub-hash merges flat; a gem key left outside
    # extensions: raises rather than silently meaning something else to Formtastic.
    def merge_filter_extensions(attribute, options)
      stray = options.keys.map(&:to_sym) & STRAY_KEYS
      if stray.any?
        raise ArgumentError, "filter :#{attribute}: #{stray.map(&:inspect).join(', ')} "                              "belong inside extensions: { ... }"
      end

      extensions = options[:extensions] || {}
      unknown = extensions.keys.map(&:to_sym) - EXTENSION_KEYS
      if unknown.any?
        raise ArgumentError, "filter :#{attribute}: unknown extensions: #{unknown.map(&:inspect).join(', ')} - "                              "the gem ships #{EXTENSION_KEYS.map(&:inspect).join(', ')}"
      end

      # The host's own required:/min: are parked rather than merged: left in, the gem would read
      # a flat min: as a window policy on an input that submits one key.
      host = options.slice(*HOST_INPUT_KEYS)
      merged = options.except(*HOST_INPUT_KEYS).merge(extensions)
      host.any? ? merged.merge(HOST_INPUT_OPTIONS => host) : merged
    end
  end
end
