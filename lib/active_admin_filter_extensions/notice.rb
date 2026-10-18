# frozen_string_literal: true

require "active_admin_filter_extensions"

module ActiveAdminFilterExtensions
  # Optional, and deliberately not part of what `active_admin_filter_extensions` installs on
  # its own: Active Admin has no notion of a flash about filters, and this is presentation
  # rather than filtering. Require it explicitly to switch it on.
  #
  #   # config/initializers/active_admin.rb
  #   require "active_admin_filter_extensions/notice"
  #
  #   ActiveAdmin.register Export do
  #     default_filters_notice "Records for the last month are displayed by default"
  #     filter :created_at, as: :date_range, extensions: { default: { gteq: -> { 1.month.ago } } }
  #   end
  #
  # An index that quietly shows a slice of the table owes the admin a word about why. The
  # message is only flashed when the defaults actually took effect, so it stays quiet once the
  # admin has filtered for themselves.
  module Notice
    def default_filters_notice(message, flash_key: :notice)
      before_action only: :index do
        # Both halves are needed: that the resource declares defaults, and that this request is
        # one they apply to. Without the second the notice would also greet an admin who had
        # just filtered for themselves.
        next unless filter_defaults_apply?
        next if filter_default_values.blank?

        flash.now[flash_key] = ::MethodOrProcHelper.render_in_context(self, message)
      end
    end
  end
end

ActiveAdmin.before_load do |_app|
  ActiveAdmin::ResourceDSL.include ActiveAdminFilterExtensions::Notice
end
