# frozen_string_literal: true

require "rack/utils"

module ActiveAdminFilterExtensions
  # A URL that means the page. A bare HTML GET of the index redirects once to itself with the
  # effective filters spelled out in the query string, so the address the admin copies carries
  # the same window, the same values, for whoever opens it: a relative default is frozen to
  # the dates it came to, a per-admin default to the values this admin saw. The price: +1
  # redirect on every bare visit, and a bookmarked URL pins the defaults of the day it was
  # made rather than following the code.
  module Redirect
    # The filters as a URL can carry them, so that the two sides of the comparison below are
    # comparable at all. A value the URL drops or hands back in another shape must be absent on
    # both sides or the hop alternates with the bare address forever: an empty Array or Hash is
    # dropped by to_query entirely, ?q[k]= comes back with the blank stripped, and an Array of
    # blanks comes back as the empty Array. `false` round-trips, and is a real answer.
    def self.canonical_filters(filters)
      filters.each_with_object({}) do |(key, value), result|
        value = value.reject { |element| element != false && element.blank? } if value.is_a?(Enumerable) && !value.is_a?(Hash)
        next if value != false && value.blank?

        result[key] = value
      end
    end

    def self.included(base)
      # ActiveAdmin.before_load fires on every dev-mode reload against the same non-reloaded
      # controller class, and Ruby runs this hook on every include call - without the guard the
      # callback would be registered again on each reload.
      return if base.instance_variable_defined?(:@active_admin_filter_extensions_redirect)

      base.instance_variable_set(:@active_admin_filter_extensions_redirect, true)
      base.before_action only: :index do
        # Only where an address bar is watching. The defaults themselves do not depend on the
        # redirect - #filtering_params applies them to a CSV or JSON index all the same - so a
        # non-HTML request just keeps its one-request shape.
        next unless request.get? && request.format.html?
        # An :empty verdict renders THIS request - nothing to show, the admin's input kept on
        # screen. The canonicalizing redirect would launder the flagged value away and the
        # next request, flagless, would render the whole table.
        next if filter_policy_render_empty?

        effective = filtering_params
        # Compared against the URL's own q - not params[:q], which a sanitize: policy may
        # have already rewritten. The point of the comparison is "does the address bar tell the
        # truth about this search"; a rewritten value is exactly a lie to correct with the 302.
        requested = Rack::Utils.parse_nested_query(request.query_string)["q"]
        # `?q=` parses to an empty String; treat it the way #filtering_params does - as absent -
        # so the equality below compares Hashes on both sides.
        requested = nil unless requested.is_a?(Hash)

        effective = Redirect.canonical_filters(effective)
        requested = Redirect.canonical_filters(requested) if requested

        # One redirect, not a loop, whatever #filter_defaults_apply? has been widened to: once
        # the query string says exactly what the search runs, the two sides are equal and the
        # request passes through. An effective side EMPTIER than the URL redirects too - a
        # policy may have reset the only key, and the bare address is the truthful one.
        next if effective == (requested || {})

        # Everything in the flash is addressed to the page this redirect is on the way to:
        # messages that arrived with the request (a batch action's "n records done") and
        # anything this request wrote with flash.now (a filter policy's error). keep un-marks
        # them all for sweeping, so they ride the 302 instead of dying with it.
        flash.keep

        # This request is the one a declared notice belongs on, and it is about to answer 302,
        # so the message is written to the travelling flash.
        if (message = active_admin_config.default_filters_notice) &&
           filter_policy_errors.empty? && filter_defaults_engaged?
          # On a shared key - the default is :notice, the same key a batch action writes - the
          # arriving message wins: it names what just happened, the notice can wait.
          key = Notice.flash_key_for(active_admin_config)
          flash[key] = ::MethodOrProcHelper.render_in_context(self, message) if flash[key].blank?
        end

        redirect_to "#{request.path}?#{request.query_parameters.merge('q' => effective).to_query}"
      end
    end
  end
end
