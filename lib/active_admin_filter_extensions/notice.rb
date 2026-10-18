# frozen_string_literal: true

module ActiveAdminFilterExtensions
  # The flash that tells the admin why the index shows a slice:
  #
  #   ActiveAdmin.register Export do
  #     default_filters_notice "Records for the last month are displayed by default"
  #     filter :created_at, as: :date_range, default: { gteq: -> { 1.month.ago } }
  #   end
  #
  # An index that quietly shows a slice of the table owes the admin a word about why. The
  # message is only flashed when the defaults actually took effect, so it stays quiet once the
  # admin has filtered for themselves.
  module Notice
    def default_filters_notice(message, flash_key: :notice)
      # Declared on the resource rather than closed over, so that the redirect - which answers
      # the request the notice belongs on with a 302 - can find it and carry it across.
      config.default_filters_notice = message
      config.default_filters_notice_flash_key = flash_key

      before_action only: :index do
        # Engaged, not merely declared: the notice must not greet an admin who filtered for
        # themselves - but must speak when a required: filter just imposed its window on a
        # partly-filtered request.
        next unless filter_defaults_engaged?
        # A policy just rejected a value: the error already explains why the page shows the
        # default slice - the notice on top of it would be noise.
        next if filter_policy_errors.present?

        flash.now[flash_key] = ::MethodOrProcHelper.render_in_context(self, message)
      end
    end
  end

  module NoticeResource
    attr_accessor :default_filters_notice, :default_filters_notice_flash_key
  end
end
