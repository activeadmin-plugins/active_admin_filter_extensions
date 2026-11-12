# frozen_string_literal: true

require "rails_helper"

# The sidebar markup moved in Active Admin 4: the Current Filters section has its own id and the
# filters section renders its title inside the block.
RSpec.describe "the filters sidebar", type: :feature do
  let(:aa_v4) { ActiveAdminFilterExtensions.aa_v4? }
  let(:current_filters) { aa_v4 ? "#active_search_sidebar_section" : "#search_status_sidebar_section" }

  it "marks the filters form with a data hook" do
    visit "/admin/string_posts"

    expect(page).to have_css("#filters_sidebar_section form[data-filter-extensions-form]")
  end

  it "shows the Current Filters panel when only defaults apply" do
    visit "/admin/string_posts"

    expect(page).to have_css(current_filters, text: "keep")
  end

  it "keeps the Current Filters panel off where the resource turned it off" do
    visit "/admin/quiet_default_posts"

    expect(page).to have_css("#filters_sidebar_section")
    expect(page).to have_no_css(current_filters)
  end

  it "hides the Current Filters panel when nothing is filtered" do
    visit "/admin/no_defaults_posts"

    expect(page).to have_css("#filters_sidebar_section")
    expect(page).to have_no_css(current_filters)
  end

  it "keeps the Current Filters panel for a filter from the request" do
    visit "/admin/no_defaults_posts?q%5Btitle_cont%5D=keep"

    expect(page).to have_css(current_filters, text: "keep")
  end

  it "renders the filters title once" do
    visit "/admin/string_posts"

    if aa_v4
      expect(page).to have_css("#filters_sidebar_section h3.filters-form-title[data-filter-extensions-title]",
                               count: 1, text: "Filters")
    else
      expect(page).to have_no_css("#filters_sidebar_section .filters-form-title")
      expect(page).to have_css("#filters_sidebar_section h3", count: 1, text: "Filters")
    end
  end
end
