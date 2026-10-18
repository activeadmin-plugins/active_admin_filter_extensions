# frozen_string_literal: true

require "rails_helper"
require "rack/utils"

# The sample app registers Post once per filter input type - see spec/support/rails_template.rb.
# Every default below selects `keep me` and rejects `drop me`, so one pair of records exercises
# all of them. Capybara follows the one canonicalizing redirect, so every example asserts the
# final page.
RSpec.describe "Filter default values", type: :feature do
  before do
    AdminUser.create!(email: "admin@example.com", default_status: "published")

    Post.create!(title: "keep me", body: "keep body", status: "published",
                 position: 20, published_date: Date.new(2026, 6, 1), starred: true)
    Post.create!(title: "drop me", body: "drop body", status: "draft",
                 position: 1, published_date: Date.new(2020, 1, 1), starred: false)
  end

  describe "every filter input type" do
    {
      "string, predicate in the Hash key" => "/admin/string_posts",
      "string, predicate already in the filter name" => "/admin/scalar_posts",
      "numeric" => "/admin/numeric_posts",
      "date range" => "/admin/date_posts",
      "select" => "/admin/select_posts",
      "check boxes" => "/admin/check_boxes_posts",
      "boolean" => "/admin/boolean_posts"
    }.each do |input_type, path|
      it "applies the declared default to a #{input_type} filter" do
        visit path

        expect(page).to have_content("keep me")
        expect(page).to have_no_content("drop me")
      end
    end
  end

  # `Proc#[]` is `call`, so a Proc left in `:input_html` answers Formtastic's `[:multiple]`
  # check with a truthy Hash and a select derives `_in` instead of `_eq` - filtering nothing,
  # silently. The Proc is resolved first, the way the filters form resolves it.
  it "resolves a Proc :input_html before asking the input" do
    visit "/admin/proc_input_html_posts"

    expect(page).to have_content("keep me")
    expect(page).to have_no_content("drop me")
    expect(page).to have_select("q[status_eq]", selected: "published")
  end

  describe "a value that cannot be placed" do
    it "says so instead of guessing" do
      expect { visit "/admin/ambiguous_posts" }
        .to raise_error(ArgumentError, /filter :published_date declares a `default:`.*single value cannot say which to fill/m)
    end
  end

  # Filtering the collection is only half of it: the admin has to be able to see what the page
  # decided on their behalf, and change it. Every input type is checked, because each renders
  # its value differently and a default that filters invisibly is the thing to avoid.
  describe "the value the admin sees in the form" do
    it "shows it on a string filter" do
      visit "/admin/string_posts"

      expect(page).to have_field("q[title_cont]", with: "keep")
    end

    it "shows it on a string filter whose name carries the predicate" do
      visit "/admin/scalar_posts"

      expect(page).to have_field("q[title_cont]", with: "keep")
    end

    it "shows it on a select filter" do
      visit "/admin/select_posts"

      expect(page).to have_select("q[status_eq]", selected: "published")
    end

    it "shows it on a check boxes filter" do
      visit "/admin/check_boxes_posts"

      expect(page).to have_checked_field("q[status_in][]", with: "published")
      expect(page).to have_unchecked_field("q[status_in][]", with: "draft")
    end

    it "shows it on a boolean filter" do
      visit "/admin/boolean_posts"

      expect(page).to have_select("q[starred_eq]", selected: "Yes")
    end

    it "shows it on both ends of a date range filter" do
      visit "/admin/date_posts"

      expect(page).to have_field("q[published_date_gteq]", with: "2026-01-01")
      expect(page).to have_field("q[published_date_lteq]", with: "")
    end

    it "shows it on a numeric filter, with the predicate its Hash named selected" do
      visit "/admin/numeric_posts"

      expect(page).to have_field("q[position_gt]", with: "10")
    end

    it "shows the one read off the signed in admin" do
      visit "/admin/admin_preference_posts"

      expect(page).to have_select("q[status_eq]", selected: "published")
    end

    it "shows everything once the field is blanked and the form submitted" do
      visit "/admin/string_posts"
      fill_in "q[title_cont]", with: ""
      click_button "Filter"

      expect(page).to have_content("keep me")
      expect(page).to have_content("drop me")
    end

    it "leaves a resource that declares no default alone" do
      visit "/admin/plain_posts"

      expect(page).to have_content("keep me")
      expect(page).to have_content("drop me")
    end
  end

  describe ":if and :unless" do
    it "neither renders a denied filter nor lets it impose its default" do
      visit "/admin/conditional_posts"

      # `title` is denied by `:if`, `body` by `:unless`: their inputs are gone, and their
      # defaults are not in force either - `drop me` is excluded by the `status` filter alone.
      expect(page).to have_no_field("q[title_cont]")
      expect(page).to have_no_field("q[body_cont]")
      expect(page).to have_field("q[status_eq]")
    end

    it "renders the index when every filter of the resource is denied" do
      visit "/admin/all_hidden_posts"

      expect(page).to have_content("keep me")
      expect(page).to have_content("drop me")
    end

    it "applies the default of the filter its condition allows" do
      visit "/admin/conditional_posts"

      expect(page).to have_content("keep me")
      expect(page).to have_no_content("drop me")
    end
  end

  describe "a default read off the signed in admin" do
    it "filters on what the admin saved" do
      visit "/admin/admin_preference_posts"

      expect(page).to have_content("keep me")
      expect(page).to have_no_content("drop me")
    end

    it "applies no filter when the admin saved nothing" do
      AdminUser.update_all(default_status: nil)

      visit "/admin/admin_preference_posts"

      expect(page).to have_content("keep me")
      expect(page).to have_content("drop me")
    end
  end

  describe "default_filters_notice" do
    it "tells the admin why the list is cut down" do
      visit "/admin/notice_posts"

      expect(page).to have_content("Showing the kept ones by default")
    end

    it "stays quiet once the admin has filtered for themselves" do
      visit "/admin/notice_posts"
      fill_in "q[title_cont]", with: "drop"
      click_button "Filter"

      expect(page).to have_no_content("Showing the kept ones by default")
    end
  end

  describe "requests that carry no q of their own" do
    it "keeps the default while paging" do
      visit "/admin/string_posts?page=1"

      expect(page).to have_no_content("drop me")
    end

    # The download link is built from params, which carry no `q` while the index is showing its
    # declared defaults, so the CSV request has to derive them again to match the screen.
    it "exports the filtered collection to CSV, not the whole table" do
      visit "/admin/string_posts"
      click_link "CSV"

      expect(page.body).to include("keep me")
      expect(page.body).to_not include("drop me")
    end
  end

  # Clear Filters strips `q[`, `page`, `utf8` and `commit` from the query string, which is the
  # state a first visit is in, so it returns the page to its declared defaults rather than to an
  # empty filter set.
  it "returns to the defaults after Clear Filters", :js do
    visit "/admin/string_posts"
    fill_in "q[title_cont]", with: ""
    click_button "Filter"
    expect(page).to have_content("drop me")

    click_link "Clear Filters"

    expect(page).to have_content("keep me")
    expect(page).to have_no_content("drop me")
  end

end
