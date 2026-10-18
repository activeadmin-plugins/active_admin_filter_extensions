# frozen_string_literal: true

require "ipaddr"

module ActiveAdminFilterExtensions
  # Value policies on a filter: what the home-grown index before_actions did, as options.
  #
  #   filter :ip_contains, as: :string,
  #          extensions: { sanitize: ->(value) { value.sub(%r{/+\z}, "") },
  #                    validate: :ip }
  #
  #   filter :title_cont, as: :string,
  #          extensions: { default:  "acme",
  #                    validate: ->(value) { "Title filter must not contain digits." if value.match?(/\d/) } }
  #
  # `sanitize:` rewrites the value in place before anything reads it - before validation and,
  # in the :redirect mode, before the redirect decision, so the URL carries the value that was
  # actually searched. `validate:` is a callable returning nil for a good value or a message
  # (a String, or a Symbol naming an i18n key under active_admin_filter_extensions.*) - or the
  # name of a built-in (validate: :ip, sanitize: :digits). Callables are instance_exec'd against the controller, like `default:`.
  #
  # On a violation the policy is :reset, the shape every app of this size hand-rolled: the
  # offending key is deleted from `q`, the message lands in flash[:error], and the filter's
  # declared `default:` - if any - refills through the ordinary merge. The defaults notice
  # stays quiet on that render: the error already explains why the page shows the default
  # slice.
  module Policies
    # A callable is itself, a Symbol names a built-in, anything else is a loud typo.
    def self.resolve_built_in(kind, built_in, value)
      return value if value.respond_to?(:call)

      built_in.fetch(value) do
        raise ArgumentError, "unknown built-in #{kind} #{value.inspect} - " \
                             "the gem ships #{built_in.keys.map(&:inspect).join(', ')}"
      end
    end

    # Validators the gem ships. Each takes the sanitized String value and answers nil (good)
    # or an i18n key Symbol.
    module Validators
      IP = lambda do |value|
        IPAddr.new(value.to_s)
        nil
      rescue IPAddr::Error
        :invalid
      end

      # An integer literal that fits a PG int4 - what every integer column cast accepts.
      INT4 = ((-2**31)..(2**31 - 1))
      INTEGER = lambda do |value|
        :invalid unless value.to_s.match?(/\A-?\d+\z/) && INT4.cover?(value.to_i)
      end

      BUILT_IN = { ip: IP, integer: INTEGER }.freeze

      def self.resolve(validator)
        Policies.resolve_built_in("validator", BUILT_IN, validator)
      end
    end

    # Sanitizers the gem ships. Each takes the raw String value and answers the value to
    # actually search - idempotent, as every sanitizer must be.
    module Sanitizers
      DIGITS = ->(value) { value.to_s.gsub(/\D/, "") }

      BUILT_IN = { digits: DIGITS }.freeze

      def self.resolve(sanitizer)
        Policies.resolve_built_in("sanitizer", BUILT_IN, sanitizer)
      end
    end

    module ResourcePolicyDSL
      # An index that answers no question until it is asked one: with no filter in the
      # request (and none imposed by a default), render an empty collection with the notice
      # instead of the whole table. Resource-level on purpose: "any filter at all" belongs
      # to no single filter.
      def require_any_filter(notice: nil)
        config.require_any_filter_notice = notice || :require_any_filter
      end
    end

    module ResourcePolicySettings
      attr_accessor :require_any_filter_notice
    end

    module Controller
      def self.included(base)
        # Guarded the same way Redirect is: before_load re-fires on every dev reload.
        return if base.instance_variable_defined?(:@active_admin_filter_extensions_guard)

        base.instance_variable_set(:@active_admin_filter_extensions_guard, true)
        base.before_action only: :index do
          enforce_filter_value_policies
        end
      end

      protected

      # Attributes whose policy rejected a value on this request. The defaults notice reads
      # this to stay quiet - one render, one message.
      def filter_policy_errors
        @filter_policy_errors ||= []
      end

      # Keys a :reset dropped this request. Their declared defaults refill regardless of the
      # usual gate - the form always sends commit, and a refill promise that holds only on
      # hand-typed URLs is not one.
      def filter_policy_reset_keys
        @filter_policy_reset_keys ||= []
      end

      def enforce_filter_value_policies
        q = params[:q]
        return enforce_require_any_filter if q.blank? || !q.respond_to?(:each_pair)

        visible_filters.each do |attribute, options|
          # A :reject already answered this request with a redirect; a second violation must
          # not answer it again.
          return if performed?

          next unless options.values_at(:sanitize, :validate, :max_range, :min).any?

          keys = policy_search_keys(attribute, options)
          enforce_scalar_policies(q, attribute, options, keys | sibling_predicate_keys(q, keys))
          enforce_window_policies(q, attribute, options, keys)
        end

        enforce_with_groups(q) unless performed?
        # Last, not first: a policy may just have reset the only question the request asked,
        # and the guard must notice within THIS request - CSV gets no second hop.
        enforce_require_any_filter unless performed?
      end

      def enforce_require_any_filter
        notice = active_admin_config.require_any_filter_notice
        return if notice.nil? || any_declared_filter_answered?

        @filter_policy_render_empty = true
        # Active Admin reads a q-less index as "this table has no rows" and renders the blank
        # slate, Create link and all; a present-but-empty q renders an empty result instead.
        params[:q] ||= {}
        flash.now[:warning] =
          notice.is_a?(String) ? notice : I18n.t(notice, scope: :active_admin_filter_extensions,
                                                 default: :require_any_filter)
      end

      # Ransack silently ignores a condition nobody declared - junk, a stale bookmark after
      # a filter rename, a predicate-less stem - and ignored is not asked. A key counts only
      # when a declared filter submits it as-is (scope-named filters carry no predicate), or
      # when it carries a real predicate on a declared filter's attribute.
      def any_declared_filter_answered?
        # A scope tab is a question, and the one Active Admin puts a count on: answering it
        # with an empty page and "specify at least one filter" contradicts the tab.
        return true if params[:scope].present?

        exact = visible_filters.flat_map { |attribute, options| policy_search_keys(attribute, options) }
        bases = exact.map { |key| strip_ransack_predicate(key) }

        filtering_params.any? do |key, value|
          next false unless value.present? || value == false

          key = key.to_s
          exact.include?(key) ||
            (key != strip_ransack_predicate(key) && bases.include?(strip_ransack_predicate(key)))
        end
      end

      def enforce_with_groups(q)
        # Membership is judged on the normalized request: a blank-array partner would pass a
        # raw present? check while Ransack drops it - half the group executing silently.
        answered = requested_filtering_params || {}
        with_groups.each do |keys|
          members = with_group_members(keys)
          present = members.select { |member| member.any? { |key| answered.key?(key) } }
          next if present.empty? || present.size == members.size

          filter_policy_errors << keys
          filter_policy_reset_keys.concat(keys)
          names = keys.map { |k| strip_ransack_predicate(k).humanize }.uniq.join(" and ")
          flash.now[:warning] = I18n.t(:given_together, scope: :active_admin_filter_extensions,
                                       filters: names)
          present.flatten.each { |key| q.delete(key) }
        end
      end

      # A group's members, not its keys: a two-ended filter submits two of them and is answered
      # by either bound - the touched-is-answered rule required: already follows. Counted as
      # separate keys, one bound beside the partner read as a half-answered group.
      def with_group_members(keys)
        keys.group_by { |key| strip_ransack_predicate(key) }.values
      end

      # `with: :year_eq` on a filter: its own search keys and the named partners are one
      # group - some-but-not-all answered resets the present ones with the warning. Declared
      # on either member; mirrored declarations dedupe to the one group they both name.
      def with_groups
        groups = visible_filters.filter_map do |attribute, options|
          partners = options[:with]
          next unless partners

          (policy_search_keys(attribute, options) + Array(partners).map(&:to_s)).uniq.sort
        end.uniq

        # Overlapping groups are one question: resetting half of one must not orphan the
        # other group's membership through the shared key.
        groups.each_with_object([]) do |keys, merged|
          overlapping, rest = merged.partition { |group| (group & keys).any? }
          merged.replace(rest << (overlapping.flatten + keys).uniq.sort)
        end
      end

      # The filter's own predicate dropdown submits _gt/_lt/_not_eq and friends beside the
      # derived head key; a value policy guarding only the head leaves the same column one
      # dropdown click from unpoliced. Siblings = request keys naming the same attribute.
      def sibling_predicate_keys(q, keys)
        bases = keys.map { |key| strip_ransack_predicate(key) }
        q.keys.select { |key| bases.include?(strip_ransack_predicate(key)) }
      end

      def strip_ransack_predicate(name)
        # Kept for the unit suite, which deliberately runs without Ransack (or Rails) loaded.
        return name.to_s unless defined?(::Ransack::Predicate)

        name = name.to_s.dup
        ::Ransack::Predicate.detect_and_strip_from_string!(name)
        name
      end

      # Deriving a key needs a resource Ransack can search; a proxy page backed by an HTTP API
      # has none, and a policy must not turn its every index into a 500. On such pages the
      # declared filter name IS the submitted key, so fall back to it.
      def policy_search_keys(attribute, options)
        filter_search_keys(attribute, options)
      rescue ArgumentError
        fallback_search_key_attributes << attribute
        [attribute.to_s]
      end

      # Which filters got their key from the fallback rather than from their input. A window
      # policy reads this: one key is a configuration error when the input said so, and merely
      # unknowable when nothing could ask the input.
      def fallback_search_key_attributes
        @fallback_search_key_attributes ||= []
      end

      def enforce_scalar_policies(q, attribute, options, keys)
        return unless options[:sanitize] || options[:validate]

        keys.each do |key|
            return if performed?

            value = q[key]
            next if value.nil? || (value.is_a?(String) && value.blank?)

            original = value

            # A `:check_boxes` or multi-select filter submits an Array of Strings - the shape
            # that input legitimately has - so the policies judge it element by element. Any
            # other shape (a Hash, a nested Array) executes byte-identically to the scalar on
            # Ransack's side and is a bypass, not a shape to ignore.
            unless policed_value_shape?(value)
              apply_invalid_filter_policy(attribute, options, scalar_reset_scope(options, keys, key), :invalid)
              next
            end

            if (sanitizer = options[:sanitize])
              sanitizer = Sanitizers.resolve(sanitizer)
              sanitized = sanitize_policed_value(attribute, sanitizer, value)
              value = sanitized
              q[key] = value
            end

            next unless (validator = options[:validate])

            validator = Validators.resolve(validator)
            # Blank ELEMENTS are the ones #requested_filtering_params discards before searching -
            # ?q[k][]=&q[k][]=draft is the shape a multi-select submits - so judging one refuses
            # a value nothing searches and resets a legitimate selection. A blank scalar is a
            # different thing and still judged: the sanitizer may have just emptied it.
            elements = value.is_a?(Array) ? value.reject(&:blank?) : [value]
            message = elements.lazy
                              .filter_map { |element| ::MethodOrProcHelper.render_in_context(self, validator, element) }.first
            # nil AND false mean "valid" - `condition && "message"` is how Ruby writes these.
            next unless message

            # :empty promises the ADMIN'S input stays on screen; the sanitized attempt
            # searched nothing, so it has nothing to show for itself.
            q[key] = original if options.fetch(:on_invalid, :reset) == :empty
            apply_invalid_filter_policy(attribute, options, scalar_reset_scope(options, keys, key), message)
          end
      end

      # A String, or an Array of Strings - what a multi-valued input submits.
      def policed_value_shape?(value)
        value.is_a?(String) || (value.is_a?(Array) && value.all?(String))
      end

      # Element-wise for an Array, so a multi-valued filter is sanitized the way it is
      # submitted. On dup'd copies: a sanitizer that mutates in place and returns the same
      # object would otherwise be compared against itself and wave its loop through.
      def sanitize_policed_value(attribute, sanitizer, value)
        return value.map { |element| sanitize_policed_value(attribute, sanitizer, element) } if value.is_a?(Array)

        sanitized = ::MethodOrProcHelper.render_in_context(self, sanitizer, value.dup).to_s
        # The sanitized value lands in the URL and comes back for another pass - a sanitizer
        # that keeps rewriting its own output redirect-loops the index into unreachability.
        # Catch it on the first request instead.
        if sanitized != value &&
           ::MethodOrProcHelper.render_in_context(self, sanitizer, sanitized.dup).to_s != sanitized
          raise ArgumentError,
                "filter :#{attribute}'s sanitize: is not idempotent " \
                "(#{value.inspect} -> #{sanitized.inspect} -> keeps changing) - " \
                "that is an infinite redirect"
        end

        sanitized
      end

      # On a window-policied filter a value violation resets ALL its keys, not just the
      # offender: half the admin's window completed from the default pair is a window nobody
      # asked for and nothing validated.
      def scalar_reset_scope(options, keys, key)
        options[:max_range] || options[:min] ? keys : [key]
      end

      # `max_range:` / `min:` treat the two bounds as one window: a violation drops the PAIR -
      # a bad gteq with a good lteq is still not the range the admin meant - and the declared
      # default refills.
      def enforce_window_policies(q, attribute, options, keys)
        # A :reject value policy may just have answered this request.
        return if performed?
        return unless options[:max_range] || options[:min]

        unless keys.size == 2
          # Nothing could ask the input what it submits, so one key is not a verdict about the
          # declaration - and raising here is the 500 the fallback exists to prevent.
          return warn_underivable_window(attribute) if fallback_search_key_attributes.include?(attribute)

          raise ArgumentError,
                "filter :#{attribute} declares max_range:/min: but its input submits "                 "#{keys.join(' and ')} - a window policy needs a two-ended input"
        end

        from_raw, to_raw = q.values_at(*keys)
        return if from_raw.blank? && to_raw.blank?

        violation = window_violation(options, from_raw, to_raw)
        return unless violation

        # The fallback's own sanity is checked once, at default materialization - in every
        # mode, not only on the resetting path.
        apply_invalid_filter_policy(attribute, options, keys, violation.first, violation.last)
      end

      # Once per resource: an index is hot, and the declaration is the same on every request.
      def warn_underivable_window(attribute)
        warned = self.class.instance_variable_get(:@extensions_underivable_windows) ||
                 self.class.instance_variable_set(:@extensions_underivable_windows, [])
        return if warned.include?(attribute)

        warned << attribute
        policy_logger&.warn(
          "filter :#{attribute} declares max_range:/min: but its search key could not be " \
          "derived, so the window is not enforced - name the predicates with a Hash"
        )
        nil
      end

      # Kept for the unit suite, which deliberately runs without Rails loaded.
      def policy_logger
        ::Rails.logger if defined?(::Rails)
      end

      def window_violation(options, from_raw, to_raw)
        from = parse_window_bound(from_raw)
        to   = parse_window_bound(to_raw)

        return [:range_invalid, {}] if (from_raw.present? && from.nil?) || (to_raw.present? && to.nil?)
        return [:range_invalid, {}] if from && to && from > to

        floor = window_floor(options)

        if floor && [from, to].compact.any? { |bound| bound < floor }
          return [:before_floor, { floor: floor.to_date }]
        end

        if (max = options[:max_range])
          # An upper bound alone is an infinitely wide window - the outage query the cap
          # exists to refuse.
          return [:range_too_wide, { limit: window_limit_text(max) }] if from.nil? && to

          if from
            # An open upper bound is measured against now; a FUTURE lower bound with no upper
            # bound selects a not-yet-written window and passes - measuring it against now
            # would read it as inverted.
            return nil if to.nil? && from >= Time.current
            return [:range_too_wide, { limit: window_limit_text(max) }] if (to || Time.current) - from > max
          end
        end

        # A min: standing alone still refuses a window with no lower bound - everything
        # before the floor is the query the floor exists to refuse. After max_range:, whose
        # too-wide verdict is the more actionable one when both are declared.
        return [:before_floor, { floor: floor.to_date }] if from.nil? && to && floor

        nil
      end

      # The cap in the units it was declared in: divided into whole days, every cap shorter than
      # one reported itself as "0 days".
      def window_limit_text(max)
        max.is_a?(::ActiveSupport::Duration) ? max.inspect : "#{max.to_i / 1.day} days"
      end

      # `min:` resolved for this request, once. nil imposes nothing - that is how a per-admin
      # floor opts out, the way a nil default: does.
      def window_floor(options)
        floor = options[:min]
        return nil unless floor

        # in_time_zone, not to_time: the bounds are parsed in Time.zone, and Date#to_time speaks
        # the SERVER zone - apart, a floor-equal bound is off by the offset.
        ::MethodOrProcHelper.render_in_context(self, floor)&.in_time_zone
      end

      def parse_window_bound(raw)
        return nil if raw.blank?
        # An Array/Hash-wrapped bound would date-parse via #to_s while Ransack silently drops
        # the wrapped condition - a bypass, not a date. Non-String time-likes stay parseable:
        # defaults materialize as Time/Date objects.
        return nil unless raw.is_a?(String) || raw.respond_to?(:to_time)

        Time.zone.parse(raw.to_s)
      rescue ArgumentError, TypeError
        nil
      end

      # What a violated policy does, by name. :reset (default) drops the key(s) and lets the
      # declared default refill; :reject bounces back the way it came; :empty renders nothing
      # but keeps the admin's input on screen with the message.
      def apply_invalid_filter_policy(attribute, options, keys, message, interpolations = {})
        filter_policy_errors << attribute
        text = filter_policy_message(attribute, options, message, interpolations)

        case options.fetch(:on_invalid, :reset)
        when :reset
          reset_violating_filter_keys(text, keys)
        when :reject
          # Only where a redirect means something. A CSV or JSON index is answered in one
          # request everywhere else in the gem, a flash it cannot render would be lost, and
          # url_for drops the format - so off the HTML path the export is bounded the :reset way.
          return reset_violating_filter_keys(text, keys) unless request.format.html?

          flash[:error] = text
          # Browsers keep the original Referer across a 302, so when back IS this index the
          # bounce would re-reject itself to the browser's redirect cap. Home instead.
          referer_path = begin
            URI.parse(request.referer.to_s).path
          rescue URI::InvalidURIError
            nil
          end
          if referer_path == request.path
            redirect_to url_for(action: :index)
          else
            redirect_back fallback_location: url_for(action: :index)
          end
        when :empty
          flash.now[:error] = text
          @filter_policy_render_empty = true
        else
          raise ArgumentError, "on_invalid: #{options[:on_invalid].inspect} - "                                "must be :reset, :reject or :empty"
        end
      end

      # Drop the offending key(s) and let the declared default refill through the merge.
      def reset_violating_filter_keys(text, keys)
        flash.now[:error] = text
        filter_policy_reset_keys.concat(keys)
        keys.each { |key| params[:q].delete(key) }
      end

      # Read by apply_filtering: an :empty policy keeps the request intact - the form must
      # still show what the admin typed - and blanks the collection instead.
      def filter_policy_render_empty?
        !!@filter_policy_render_empty
      end

      def filter_policy_message(attribute, options, message, interpolations = {})
        return message if message.is_a?(String)

        values = { filter: options[:label] || attribute.to_s.humanize }.merge(interpolations)
        # `message:` on the filter speaks for every symbolic violation of this filter - the
        # app's own words without duplicating a whole validator to say them. Interpolated, so
        # those words can name %{limit} and %{floor} as the shipped texts do.
        if (override = options[:message])
          return begin
            I18n.interpolate(override, values)
          rescue I18n::ArgumentError
            override
          end
        end

        # The English texts ship as plain i18n (config/locales/en.yml); an application
        # overrides them under the same keys.
        policy_translation(message, values)
      end

      # A validate: may answer any Symbol in the gem's scope, including the parameterized ones -
      # which have nothing to interpolate from. A violation message is not worth a 500, so an
      # unknown key and a missing interpolation both read as :invalid.
      def policy_translation(message, values)
        I18n.t(message, scope: :active_admin_filter_extensions, raise: true, **values)
      rescue I18n::ArgumentError
        I18n.t(:invalid, scope: :active_admin_filter_extensions, **values)
      end
    end
  end
end
