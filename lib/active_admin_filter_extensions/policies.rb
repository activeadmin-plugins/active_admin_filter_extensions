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
        return if q.blank? || !q.respond_to?(:each_pair)

        visible_filters.each do |attribute, options|
          next unless options.values_at(:sanitize, :validate).any?

          keys = filter_search_keys(attribute, options)
          enforce_scalar_policies(q, attribute, options, keys)
        end
      end

      def enforce_scalar_policies(q, attribute, options, keys)
        return unless options[:sanitize] || options[:validate]

        keys.each do |key|
            value = q[key]
            next if value.nil? || (value.is_a?(String) && value.blank?)

            # Ransack executes a Hash- or Array-wrapped value byte-identically to the scalar;
            # a policed key that is not a plain string is a bypass, not a shape to ignore.
            unless value.is_a?(String)
              apply_invalid_filter_policy(attribute, options, [key], :invalid)
              next
            end

            if (sanitizer = options[:sanitize])
              sanitizer = Sanitizers.resolve(sanitizer)
              # On dup'd copies: a sanitizer that mutates in place and returns the same
              # object would otherwise be compared against itself and wave its loop through.
              sanitized = ::MethodOrProcHelper.render_in_context(self, sanitizer, value.dup).to_s
              # The sanitized value lands in the URL and comes back for
              # another pass - a sanitizer that keeps rewriting its own output redirect-loops
              # the index into unreachability. Catch it on the first request instead.
              if sanitized != value &&
                 ::MethodOrProcHelper.render_in_context(self, sanitizer, sanitized.dup).to_s != sanitized
                raise ArgumentError,
                      "filter :#{attribute}'s sanitize: is not idempotent "                       "(#{value.inspect} -> #{sanitized.inspect} -> keeps changing) - "                       "that is an infinite redirect"
              end

              value = sanitized
              q[key] = value
            end

            next unless (validator = options[:validate])

            message = ::MethodOrProcHelper.render_in_context(self, Validators.resolve(validator), value)
            # nil AND false mean "valid" - `condition && "message"` is how Ruby writes these.
            apply_invalid_filter_policy(attribute, options, [key], message) if message
          end
      end

      # What a violated policy does, by name. :reset (the only one yet) drops the key(s) and
      # lets the declared default refill.
      def apply_invalid_filter_policy(attribute, options, keys, message, interpolations = {})
        filter_policy_errors << attribute
        text = filter_policy_message(attribute, options, message, interpolations)

        case options.fetch(:on_invalid, :reset)
        when :reset
          flash.now[:error] = text
          filter_policy_reset_keys.concat(keys)
          keys.each { |key| params[:q].delete(key) }
        else
          raise ArgumentError, "on_invalid: #{options[:on_invalid].inspect} - "                                "must be :reset"
        end
      end

      def filter_policy_message(attribute, options, message, interpolations = {})
        return message if message.is_a?(String)
        # `message:` on the filter speaks for every symbolic violation of this filter - the
        # app's own words without duplicating a whole validator to say them.
        return options[:message] if options[:message]

        values = { filter: options[:label] || attribute.to_s.humanize }.merge(interpolations)
        # The English texts ship as plain i18n (config/locales/en.yml); an application
        # overrides them under the same keys. Unknown symbols read as :invalid.
        I18n.t(message, scope: :active_admin_filter_extensions,
                        default: :invalid, **values)
      end
    end
  end
end
