# frozen_string_literal: true

require "spec_helper"
require "active_admin_filter_extensions/redirect"

# ActiveAdmin.before_load fires on every dev-mode reload against the same non-reloaded gem
# classes, and Ruby runs the `included` hook on every include call even when the module is
# already in the ancestors - so the hook must not register its callback again.
RSpec.describe ActiveAdminFilterExtensions::Redirect do
  let(:base) do
    Class.new do
      def self.registered_callbacks
        @registered_callbacks ||= []
      end

      def self.before_action(*args, &block)
        registered_callbacks << block
      end
    end
  end

  it "installs its callback once, however many times it is included" do
    3.times { base.include described_class }

    expect(base.registered_callbacks.size).to eq(1)
  end
end
