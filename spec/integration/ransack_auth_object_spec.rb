# frozen_string_literal: true

require "rails_helper"

# Active Admin 4 passes its authorization adapter to Ransack, so a model's allowlist can depend
# on the admin. The gem's own search and its search-key derivation must pass it on as well.
RSpec.describe "the Ransack auth object", type: :feature do
  it "reaches the model's allowlist from every search the index builds" do
    seen = []
    allow(Post).to receive(:ransackable_attributes).and_wrap_original do |original, auth_object = nil|
      seen << auth_object
      original.call(auth_object)
    end

    visit "/admin/string_posts"

    expected = ActiveAdminFilterExtensions.aa_v4? ? ActiveAdmin::AuthorizationAdapter : NilClass
    expect(seen).not_to be_empty
    expect(seen).to all(be_a(expected))
  end
end
