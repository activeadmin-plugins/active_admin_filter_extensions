# frozen_string_literal: true

module ActiveAdminFilterExtensions
  # `extensions: { none: true }` - a select filter's option for the records whose attribute is
  # empty. The select submits a sentinel under its own key and only the search is handed the
  # `_null` it stands for, so defaults, policies and the redirect read the request as submitted.
  module NoneOption
    # What a select derives. _not_eq and _not_in end the same way, and an OR beside their
    # `_not_null` is no reading of "none of these".
    KEY = /(?<!_not)_(eq|in)\z/
    # Where the search carries what Current Filters should call each None option it searched.
    LABELS = :@none_option_labels

    def self.null_key(key)
      "#{key.to_s.sub(KEY, '')}_null"
    end

    # @return [Hash] the search values, every sentinel under `keys` turned into `_null`
    def self.search_params(params, keys, sentinel)
      groupings = []
      searched = params.each_with_object({}) do |(key, value), result|
        values = Array.wrap(value)
        next result[key] = value unless keys.include?(key.to_s) && values.include?(sentinel)

        null_key = NoneOption.null_key(key)
        values = (values - [sentinel]).reject { |element| element.blank? && element != false }
        next result[null_key] = "1" if values.empty?

        # "None or Acme" is an OR, and Ransack only says OR inside a grouping.
        groupings << { "m" => "or", key.to_s => values, null_key => "1" }
      end
      return searched if groupings.empty?

      existing = searched["g"]
      existing = existing.values if existing.is_a?(Hash)
      searched.merge("g" => Array(existing) + groupings)
    end

    protected

    # What Ransack is handed in place of #filtering_params.
    def none_filter_search_params(params)
      return params if none_filter_keys.empty?

      NoneOption.search_params(params, none_filter_keys.values, ActiveAdminFilterExtensions.none_value)
    end

    # The Current Filters panel is built from the search object alone, so the label of every
    # None option this request searched rides on it, under the `_null` key it became.
    def label_none_filters(search)
      sentinel = ActiveAdminFilterExtensions.none_value unless none_filter_keys.empty?
      labels = none_filter_keys.each_with_object({}) do |(attribute, key), result|
        next unless Array.wrap(none_filter_request_value(key)).include?(sentinel)

        result[NoneOption.null_key(key)] = none_filter_label(visible_filters[attribute])
      end
      search.instance_variable_set(LABELS, labels) if labels.any?
    end

    # A none: filter's options with the None option heading its collection. The collection is
    # asked of an input built on the form's own search and view, so a Proc, a relation and a
    # filter with no collection: resolve the way the form resolves them.
    def none_filter_form_options(attribute, options, search, template)
      key = none_filter_keys[attribute.to_sym]
      return options unless key

      builder = ::ActiveAdmin::Filters::FormBuilder.new(:q, search, template, {})
      collection = build_filter_input(attribute, options, builder).collection
      if collection.is_a?(String)
        raise ArgumentError, "filter :#{attribute} declares none: but its collection is rendered " \
                             "HTML - the None option needs a collection of values to head"
      end

      sentinel = ActiveAdminFilterExtensions.none_value
      # The collection is pairs by now, and member_label:/member_value: would be sent to them.
      options = options.except(:member_label, :member_value)
                       .merge(collection: [[none_filter_label(options), sentinel]] + collection.to_a)
      # Ransack is never handed the sentinel, and the values chosen beside it sit in a grouping,
      # so the search object cannot say what is selected - the request can.
      requested = none_filter_request_value(key)
      Array.wrap(requested).include?(sentinel) ? options.merge(selected: requested) : options
    end

    private

    # The search key of every visible none: filter. Materialized on every index request, which
    # is also what refuses, loudly, a filter the None option cannot work on.
    #
    # @return [Hash] filter attribute => search key
    def none_filter_keys
      @none_filter_keys ||= visible_filters.each_with_object({}) do |(attribute, options), result|
        next unless options[:none]

        keys = filter_search_keys(attribute, options)
        input = build_filter_input(attribute, options)
        unless input.is_a?(::Formtastic::Inputs::SelectInput) && keys.size == 1 && keys.first.match?(KEY)
          raise ArgumentError, "filter :#{attribute} declares none: but its #{input.as} input submits " \
                               "#{keys.join(' and ')} - the None option needs a select that submits _eq or _in"
        end

        result[attribute.to_sym] = keys.first
      end
    end

    def none_filter_request_value(key)
      filtering_params.find { |name, _| name.to_s == key }&.last
    end

    def none_filter_label(options)
      return options[:none].to_s unless options[:none] == true

      I18n.t(:none, scope: :active_admin_filter_extensions, default: "None")
    end
  end
end
