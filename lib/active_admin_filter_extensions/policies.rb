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
  # (a String, or a Symbol naming an i18n key under active_admin_filter_extensions.*).
  # Callables are instance_exec'd against the controller, like `default:`.
  #
  # On a violation the policy is :reset, the shape every app of this size hand-rolled: the
  # offending key is deleted from `q`, the message lands in flash[:error], and the filter's
  # declared `default:` - if any - refills through the ordinary merge. The defaults notice
  # stays quiet on that render: the error already explains why the page shows the default
  # slice.
  module Policies
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

            message = ::MethodOrProcHelper.render_in_context(self, validator, value)
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

        values = { filter: options[:label] || attribute.to_s.humanize }.merge(interpolations)
        # The English texts ship as plain i18n (config/locales/en.yml); an application
        # overrides them under the same keys. Unknown symbols read as :invalid.
        I18n.t(message, scope: :active_admin_filter_extensions,
                        default: :"active_admin_filter_extensions.invalid", **values)
      end
    end
  end
end
