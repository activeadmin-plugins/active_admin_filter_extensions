# frozen_string_literal: true

module ActiveAdminFilterExtensions
  # Everything `filter ..., default:` means: which requests the declared defaults apply to, what
  # they come to on this one, and which Ransack key each value lands under.
  #
  # Included rather than prepended - none of it replaces anything Active Admin defines, and a
  # resource is meant to be able to override the seams here in its own `controller do` block.
  # The one method that does replace Active Admin's is in DataAccess.
  module FilterDefaults
    # Ransack reads more than conditions out of q: `m` switches the combinator to OR - turning
    # a required, capped window into `window OR anything` - and `g` nests whole condition
    # groups no value policy ever saw. No Active Admin filter form submits them; here they are
    # a bypass, not an answer, and they are stripped before anything reads the request.
    RANSACK_STRUCTURE = %w[m g c s conditions sorts groupings combinator].freeze

    protected

    # The filter values the collection is searched with. Override to change what the index
    # filters on without reaching into `params`.
    #
    # Whatever the request asked for wins over a default, so that an override of
    # #filter_defaults_apply? which lets defaults through on a partly filtered request keeps
    # the values that were actually asked for.
    #
    # @return [Hash, ActionController::Parameters] values passed to Ransack
    def filtering_params
      requested = requested_filtering_params
      return requested || {} unless filter_defaults_apply?

      defaults = filter_default_values
      return requested || {} if defaults.blank?

      defaults.merge(requested || {})
    end

    # Whether any default actually reaches this request's search - what the notice announces.
    def filter_defaults_engaged?
      requested = requested_filtering_params || {}
      # At least one default must actually reach the search: a widened apply? beside a
      # request that answered every defaulted key itself engaged nothing.
      filter_defaults_apply? && filter_default_values.keys.any? { |key| requested[key].nil? }
    end

    # Whether the request is one the declared defaults should apply to. Override to widen it -
    # a resource that always carries its customer in `q`, say, still wants its defaults on the
    # first visit:
    #
    #   def filter_defaults_apply?
    #     super || params[:q].keys == %w[customer_id_eq]
    #   end
    #
    # `commit` marks a submission of the filters form: submitting it with every field blank
    # sends no `q` at all, because the form disables empty fields on submit, so `commit` is
    # what tells "show me everything" apart from a first visit. Clearing the filters drops
    # `commit` along with `q`, so Clear Filters returns the page to its declared defaults.
    # Judged on the NORMALIZED request: a q holding nothing but blanks or structural keys is
    # a bare request on every format - the CSV gets no canonicalizing hop to say otherwise.
    def filter_defaults_apply?
      requested_filtering_params.blank? && params[:commit].blank?
    end

    # @return [Hash] the search values declared with `filter ..., default:`
    def filter_default_values
      @filter_default_values ||= visible_filters.each_with_object({}) do |(attribute, options), result|
        next unless options.key?(:default)

        add_filter_default_value(result, attribute, options)
      end
    end

    private

    def requested_filtering_params
      requested = params[:q]
      requested = requested.to_unsafe_h if requested.respond_to?(:to_unsafe_h)
      # `?q=` parses to an empty String - blank, so the defaults apply, but not a Hash, so it
      # must not reach the merge. Anything else non-Hash is junk Ransack would ignore anyway.
      return nil unless requested.is_a?(Hash)

      # A blank value is no answer: Ransack strips it before searching, so letting it clobber
      # a default in the merge - or count as "this key was answered" for a required: window -
      # turns ?q[k]= into a full-table scan wearing an answered-looking URL. An Array answers
      # with what is left of it once ITS blanks are gone: [""] is as empty as "".
      requested = requested.transform_values do |value|
        value.is_a?(Array) ? value.reject { |element| element.blank? && element != false } : value
      end
      requested.reject do |key, value|
        RANSACK_STRUCTURE.include?(key.to_s) || (value.blank? && value != false)
      end
    end

    # A default is a value, and where that value goes is the input's business - see SearchKeys.
    #
    #   filter :status, as: :select,      default: "active"
    #   filter :author, as: :check_boxes, default: [1, 2]
    #   filter :created_at, as: :date_range, default: -> { 1.week.ago.. }
    #
    # A Hash still says the predicates outright, for when the input's own is not the one you
    # want (`default: { eq: "acme" }` on a string filter that would otherwise search `_cont`).
    #
    # Only a Proc is called - unlike `:if` and `:unless`, a Symbol here is a value, not a
    # method to send.
    def add_filter_default_value(result, attribute, options)
      default = options[:default]
      default = instance_exec(&default) if default.is_a?(Proc)
      return if default.nil?

      if default.is_a?(Hash)
        default.each do |predicate, value|
          value = instance_exec(&value) if value.is_a?(Proc)
          result["#{attribute}_#{predicate}"] = value unless value.nil?
        end
      else
        assign_derived_filter_default(result, attribute, options, default)
      end
    end
    # A Range fills a two-ended input, one bound per end, and an endless or beginless one fills
    # only the end it has. Anything else is a single value for a single-ended input.
    def assign_derived_filter_default(result, attribute, options, default)
      names = filter_search_keys(attribute, options)

      if default.is_a?(Range)
        unless names.size == 2
          raise_filter_default_error(attribute, "a Range needs an input with two ends, and this one submits #{names.join(' and ')}")
        end

        result[names.first] = default.begin unless default.begin.nil?
        result[names.last] = default.end unless default.end.nil?
      else
        unless names.size == 1
          raise_filter_default_error(attribute, "this input submits #{names.join(' and ')}, so a single value cannot say which to fill - give a Range, or name the predicates with a Hash")
        end

        result[names.first] = default
      end
    end

  end
end
