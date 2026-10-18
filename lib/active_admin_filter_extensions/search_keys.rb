# frozen_string_literal: true

module ActiveAdminFilterExtensions
  # Which Ransack key(s) a filter's input actually submits - derived by building the input
  # the way the sidebar would and asking it, so a declared value lands exactly where the
  # form would put it.
  module SearchKeys
    private

    # Asked against an empty search on purpose: `current_filter` otherwise answers with whatever
    # predicate the current request happens to carry, and a default is about the request that
    # carries none.
    #
    # @return [Array<String>] one key, or two for a range input
    def filter_search_keys(attribute, options)
      input = build_filter_input(attribute, options)

      names =
        if input.respond_to?(:gt_input_name)
          [input.gt_input_name, input.lt_input_name]
        elsif input.respond_to?(:current_filter) && !input.seems_searchable?
          # `:string` and `:numeric` let the admin pick the predicate from a dropdown, and the
          # head of that list is what an untouched form submits. Unless the filter name already
          # carries a predicate, in which case there is no dropdown - and asking anyway raises,
          # since `current_filter` would go looking for `title_eq_cont`.
          [input.current_filter]
        else
          [input.input_name]
        end

      names.map { |name| name.to_s[/\Aq\[([^\]]+)\]/, 1] || name.to_s }
    rescue StandardError => e
      raise_filter_default_error(attribute, "could not work out which search key it submits (#{e.class}: #{e.message}) - name the predicate with a Hash instead")
    end

    def build_filter_input(attribute, options)
      builder = filter_input_builder
      options = filter_input_options(options, builder)
      as = options[:as] || builder.send(:default_input_type, attribute)
      builder.send(:namespaced_input_class, as)
             .new(builder, builder.template, builder.object, :q, attribute, options)
    end

    # `:input_html` may be a Proc, which the filters form resolves against the view before it
    # builds the input. Handing the Proc over instead is not merely incomplete, it is wrong in
    # a way nothing reports: `Proc#[]` is `call`, so Formtastic asking `input_html[:multiple]`
    # invokes it, gets a truthy Hash back, and a `:select` derives `_in` rather than `_eq`.
    def filter_input_options(options, builder)
      options = options.except(*FilterOptions::NOT_FOR_INPUT)
      return options unless options[:input_html].is_a?(Proc)

      options.merge(input_html: builder.template.instance_exec(&options[:input_html]))
    end

    # One per request rather than one per filter: #view_context builds a fresh view class every
    # time it is called, and every defaulted filter would pay for another one.
    def filter_input_builder
      @filter_input_builder ||= ::ActiveAdmin::Filters::FormBuilder.new(
        :q, active_admin_config.resource_class.ransack({}), view_context, {}
      )
    end

    def raise_filter_default_error(attribute, message)
      raise ArgumentError, "filter :#{attribute} declares a `default:` but #{message}"
    end
  end
end
