# frozen_string_literal: true

module ActiveAdminFilterExtensions
  # `extensions: { required: }` - the mandatory window: a filter whose default applies whenever
  # its own keys are absent, whatever else the request carries.
  module RequiredFilters
    protected

    # The subset of the defaults that `required: true` promotes to mandatory, grouped per
    # filter so each imposes itself all-or-nothing.
    def required_filter_default_values
      @required_filter_default_values ||= visible_filters.each_with_object({}) do |(attribute, options), result|
        next unless options[:required]
        unless options.key?(:default)
          raise ArgumentError,
                "filter :#{attribute} is required: true but declares no default: to fall back on"
        end

        # One materialization per request: the group shares filter_default_values' already
        # validated (and sanitized) values instead of resolving the Procs a second time.
        filter_default_values
        group = filter_default_values.slice(*(@filter_default_keys || {})[attribute])
        # Answered by ANY of the filter's own submitted keys, not only the ones its default
        # happens to fill: an endless default must not inject a lower bound beside an
        # upper-only request.
        result[attribute] = { defaults: group, keys: policy_search_keys(attribute, options) }
                            .merge(required_conditions(attribute, options))
      end
    end

    # required: true is unconditional. A Hash narrows it: { if: keys } imposes the window only
    # beside those keys, { unless: keys } excuses it beside those - a search pinpointing a
    # record is not a scan to box in. Keys take a Symbol or an Array; both conditions combine.
    def required_conditions(attribute, options)
      return { if: [], unless: [] } unless options[:required].is_a?(Hash)

      unknown = options[:required].keys - %i[if unless]
      if unknown.any?
        raise ArgumentError, "filter :#{attribute}: required: takes true or "                              "{ if:/unless: key(s) }, got #{unknown.map(&:inspect).join(', ')}"
      end

      { if: Array(options[:required][:if]).map(&:to_s),
        unless: Array(options[:required][:unless]).map(&:to_s) }
    end

    # The required defaults this request has not answered: only the groups NONE of whose own
    # keys the request carries, whose if: keys (if any) the request does carry, and none of
    # whose unless: keys.
    def required_filter_defaults_absent_from(requested)
      required_filter_default_values.each_with_object({}) do |(_attribute, entry), result|
        next if required_group_answered?(requested, entry[:keys])
        next if entry[:if].any? && entry[:if].none? { |key| requested[key].present? }
        next if entry[:unless].any? { |key| requested[key].present? }

        result.merge!(entry[:defaults])
      end
    end

    # Any predicate of the filter's own attribute is an answer about it - the admin picking
    # "equals" on a :string filter submits title_eq where the derived key is title_cont, and
    # completing that from the default searches two conditions on one column. Read exactly the
    # way #any_declared_filter_answered? reads a question: an exact declared key, or a real
    # predicate on the declared attribute - never a predicate-less stem Ransack ignores, which
    # would switch a mandatory window off with a key that searches nothing.
    def required_group_answered?(requested, keys)
      bases = keys.map { |key| strip_ransack_predicate(key) }

      requested.any? do |key, value|
        next false unless value.present?

        key = key.to_s
        next true if keys.include?(key)

        key != strip_ransack_predicate(key) && bases.include?(strip_ransack_predicate(key))
      end
    end
  end
end
