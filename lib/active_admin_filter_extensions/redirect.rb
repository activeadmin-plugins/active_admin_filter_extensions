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

        effective = filtering_params
        # Compared against the URL's own q - not params[:q], which a sanitize: policy may
        # have already rewritten. The point of the comparison is "does the address bar tell the
        # truth about this search"; a rewritten value is exactly a lie to correct with the 302.
        requested = Rack::Utils.parse_nested_query(request.query_string)["q"]
        # `?q=` parses to an empty String; treat it the way #filtering_params does - as absent -
        # so the equality below compares Hashes on both sides.
        requested = nil unless requested.is_a?(Hash)

        # A blank value is one the URL cannot round-trip: an empty Array or Hash is dropped
        # by to_query entirely, and ?q[k]= comes back in with the blank stripped - redirecting
        # on either alternates with the bare URL forever. Blanks stay out of the redirect.
        effective = effective.reject { |_, value| value != false && value.blank? }

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

        redirect_to "#{request.path}?#{request.query_parameters.merge('q' => effective).to_query}"
      end
    end
  end
end
