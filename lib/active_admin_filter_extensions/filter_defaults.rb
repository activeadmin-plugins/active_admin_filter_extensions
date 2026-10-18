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
    # groups no value policy ever saw. No Active Admin filter form submits them; where this gem
    # guards the filters they are a bypass, not an answer, and they are stripped before anything
    # reads the request. On a resource that declares nothing of this gem's there is no policy to
    # bypass, and `q[g]` is the app's own standard OR workaround - see #strip_ransack_structure?.
    RANSACK_STRUCTURE = %w[m g c conditions groupings combinator].freeze
    # Sorting is not a condition: it reaches Ransack untouched, and it is not an answer to the
    # question the defaults exist to answer.
    RANSACK_SORT = %w[s sorts].freeze

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
      # Materialized on every path: computing it is also what validates, loudly, that every
      # required: filter has a default: to fall back on.
      required_filter_default_values

      defaults =
        if filter_defaults_apply?
          filter_default_values
        else
          # A filter marked required: applies when ALL its own keys are absent. A request that
          # touched any of them - a half-range included - said what it wants there; completing
          # it from the default could manufacture a pair the admin never meant (an inverted
          # range, say). What a half-open range may not mean is max_range:'s business.
          required_filter_defaults_absent_from(requested || {})
        end

      defaults = defaults.merge(reset_filter_default_values)
      # A refill honors with: atomicity: pulling one member of a group pulls its partners'
      # defaults along (the materialization check guarantees they exist) - the merge must
      # not hand Ransack the half-group the enforcement just promised away.
      defaults = complete_with_groups(defaults)
      return requested || {} if defaults.blank?

      defaults.merge(requested || {})
    end

    def complete_with_groups(defaults)
      with_groups.each do |keys|
        next unless keys.any? { |key| defaults.key?(key) }

        # A member that opted out this request leaves the group uncompletable, and half a group
        # is the search the all-or-none contract refuses - so the group imposes nothing.
        next defaults = defaults.except(*keys) if keys.any? { |key| nil_default_filter_keys.include?(key) }

        defaults = filter_default_values.slice(*keys).merge(defaults)
      end
      defaults
    end

    # The keys of filters that declare a default: which resolved to nil for this request. A nil
    # Proc result imposes nothing - that is how a per-admin default opts out - so it is not the
    # missing declaration the with: completeness check refuses.
    def nil_default_filter_keys
      @nil_default_filter_keys ||= []
    end

    # The defaults of keys a policy just reset - refilled whatever filter_defaults_apply?
    # says, because the reset itself is what emptied them.
    def reset_filter_default_values
      return {} if filter_policy_reset_keys.empty?

      # By attribute, not by exact key: a sibling-predicate reset (position_gt) must still
      # refill the filter's own declared default (position_eq).
      bases = filter_policy_reset_keys.map { |key| strip_ransack_predicate(key) }
      filter_default_values.select { |key, _| bases.include?(strip_ransack_predicate(key)) }
    end

    # Whether any default actually reaches this request's search - what the notice announces.
    # Wider than #filter_defaults_apply?: a required filter engages on a partly-filtered
    # request too, as long as the request left its keys blank.
    def filter_defaults_engaged?
      requested = requested_filtering_params || {}
      if filter_defaults_apply?
        # At least one default must actually reach the search: a widened apply? beside a
        # request that answered every defaulted key itself engaged nothing.
        return filter_default_values.keys.any? { |key| requested[key].nil? }
      end

      required_filter_defaults_absent_from(requested).any?
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
      (requested_filtering_params || {}).except(*RANSACK_SORT).blank? && params[:commit].blank?
    end

    # @return [Hash] the search values declared with `filter ..., default:`
    def filter_default_values
      @filter_default_values ||= visible_filters.each_with_object({}) do |(attribute, options), result|
        next unless options.key?(:default)

        before = result.keys
        add_filter_default_value(result, attribute, options)
        added = result.keys - before
        (@filter_default_keys ||= {})[attribute] = added
        nil_default_filter_keys.concat(policy_search_keys(attribute, options)) if added.empty?
        # Value policies first: the window must be judged on what the sanitizer stored.
        validate_default_against_value_policies(attribute, options, result, result.keys - before)
        validate_default_against_policies(attribute, options, result)
      end.tap { |defaults| validate_defaults_against_with_groups(defaults) }
    end

    # A with: group is all-or-none in the fallback too: defaults answering part of a group
    # would execute the very half-group the enforcement refuses - on a bare visit, where no
    # enforcement even runs.
    def validate_defaults_against_with_groups(defaults)
      with_groups.each do |keys|
        # By member, so a half-open Range default - which fills only the end it has - answers
        # its two-ended member rather than reading as half a group.
        members = with_group_members(keys)
        answered = members.select do |member|
          member.any? { |key| defaults.key?(key) || nil_default_filter_keys.include?(key) }
        end
        next if answered.empty? || answered.size == members.size

        raise ArgumentError,
              "filters #{keys.join(', ')} are declared with: one another, but only " \
              "#{answered.flatten.join(', ')} declare defaults - the fallback must answer the " \
              "whole group or none of it"
      end
    end

    # A default the filter's own window policy would refuse is a configuration error: on the
    # non-redirected formats it would run the over-cap scan silently, forever.
    def validate_default_against_policies(attribute, options, values_by_key)
      return unless options[:max_range] || options[:min]

      # Looked up by the derived keys, not insertion order: a beginless default fills only the
      # lteq slot, and judged as a lower bound it would pass as a future-open window.
      gteq_key, lteq_key = filter_search_keys(attribute, options)
      from, to = values_by_key.values_at(gteq_key, lteq_key)
      return if from.nil? && to.nil?

      violation = window_violation(options, from, to)
      return unless violation

      raise ArgumentError,
            "filter :#{attribute} declares a default that violates its own window policy "             "(#{violation.first}) - the fallback must satisfy max_range:/min:"
    end

    # A default the filter's own validate: would refuse is the same configuration error: it
    # refills on every bare visit, fails, resets, and refills - a permanent self-inflicted
    # error banner. Judged - and stored - the way the URL will say it: sanitized, as a
    # String, because that is the value every next request actually carries.
    def validate_default_against_value_policies(attribute, options, result, keys)
      sanitizer = options[:sanitize]
      validator = options[:validate]
      return unless sanitizer || validator

      keys.each do |key|
        value = result[key]
        next if value.nil?

        # Judged the way the URL will say it: a scalar as the String it becomes, an Array
        # element by element - the shape a multi-valued input submits.
        if sanitizer
          resolved = Policies::Sanitizers.resolve(sanitizer)
          result[key] = sanitize_default_value(attribute, resolved, value)
        end
        next unless validator

        resolved_validator = Policies::Validators.resolve(validator)
        next unless default_value_strings(result[key])
                    .any? { |string| ::MethodOrProcHelper.render_in_context(self, resolved_validator, string) }

        raise ArgumentError,
              "filter :#{attribute} declares a default that violates its own validate: " \
              "policy - the fallback must be a value the filter accepts"
      end
    end

    # An Array default is submitted element by element; anything else as one String.
    def default_value_strings(value)
      value.is_a?(Array) ? value.map(&:to_s) : [value.to_s]
    end

    def sanitize_default_value(attribute, sanitizer, value)
      return value.map { |element| sanitize_default_value(attribute, sanitizer, element) } if value.is_a?(Array)
      return value if value.is_a?(Enumerable)

      sanitized = ::MethodOrProcHelper.render_in_context(self, sanitizer, value.to_s.dup).to_s
      # The same fixpoint check submitted values face: without it the CSV searches the
      # once-sanitized value while the HTML converges on another, and nobody raises.
      if ::MethodOrProcHelper.render_in_context(self, sanitizer, sanitized.dup).to_s != sanitized
        raise ArgumentError,
              "filter :#{attribute}'s sanitize: is not idempotent " \
              "(#{value.inspect} -> #{sanitized.inspect} -> keeps changing) - " \
              "a default must sanitize to a fixpoint"
      end

      sanitized
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
      strip_structure = strip_ransack_structure?
      requested.reject do |key, value|
        (strip_structure && RANSACK_STRUCTURE.include?(key.to_s)) || (value.blank? && value != false)
      end
    end

    # Whether this resource declares anything of this gem's. Only then is a structural key a
    # bypass of something; on every other resource it is the app's own search and stripping it
    # silently widens the export to the whole table.
    def strip_ransack_structure?
      return @strip_ransack_structure if defined?(@strip_ransack_structure)

      @strip_ransack_structure =
        active_admin_config.require_any_filter_notice.present? ||
        active_admin_config.default_filters_notice.present? ||
        visible_filters.any? { |_attribute, options| options.key?(:extensions) }
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
