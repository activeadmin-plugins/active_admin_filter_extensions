# frozen_string_literal: true

require "rails_helper"

# Everything of the gem's lives under the one extensions: option. Both ways out of the container
# are loud: a gem key left flat would otherwise mean something else to Formtastic (required:),
# and a typo inside would silently guard nothing.
RSpec.describe "the extensions: container", type: :feature do
  it "raises for a gem option left outside extensions:" do
    expect { visit "/admin/banana_flat_option_posts" }
      .to raise_error(ArgumentError, /:default.*belong inside extensions:/m)
  end

  it "raises for an unknown key inside extensions:" do
    expect { visit "/admin/banana_policy_key_posts" }
      .to raise_error(ArgumentError, /unknown extensions: :defult/m)
  end
end
