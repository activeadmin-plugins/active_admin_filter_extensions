# frozen_string_literal: true

require "rails_helper"

# Everything of the gem's lives under the one extensions: option. Both ways out of the container
# are loud: a gem key left flat would otherwise mean something else to Formtastic (required:),
# and a typo inside would silently guard nothing.
RSpec.describe "the extensions: container", type: :feature do
  it "reads a string-keyed container" do
    # The unknown-key check symbolizes before comparing, so "default" => ... passed it and then
    # merged under a String key the gem never reads: a declared default that quietly did nothing.
    Post.create!(title: "keep me", status: "published", position: 20)
    Post.create!(title: "drop me", status: "draft", position: 1)

    visit "/admin/string_keyed_extensions_posts"

    expect(page).to have_content("keep me")
    expect(page).to have_no_content("drop me")
  end

  it "raises for a gem option left outside extensions:" do
    expect { visit "/admin/banana_flat_option_posts" }
      .to raise_error(ArgumentError, /:default.*belong inside extensions:/m)
  end

  it "leaves a flat required: and min: to Formtastic" do
    # `filter :position, as: :numeric, min: 0` is legal Active Admin. Annexed, the gem read
    # min: as a window policy on a single-ended input and 500'd every index of the resource.
    visit "/admin/host_option_posts"

    expect(page).to have_css("input[name='q[position]'][min='0']")
  end

  it "raises for an unknown key inside extensions:" do
    expect { visit "/admin/banana_policy_key_posts" }
      .to raise_error(ArgumentError, /unknown extensions: :defult/m)
  end
end
