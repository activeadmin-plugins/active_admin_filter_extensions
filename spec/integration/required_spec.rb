# frozen_string_literal: true

require "rails_helper"
require "rack/utils"

# `required: true` promotes a filter's default from "applies to a bare request" to "applies
# whenever THIS filter's key is absent" - the mandatory window every app hand-rolled as a
# filter_defaults_apply? override. `skips_required: true` on a filter is the escape hatch: a search
# that names a unique record gets exactly what it asked for.
RSpec.describe "required: filters", type: :feature do
  let!(:kept) do
    Post.create!(title: "keep me", body: "keep body", status: "published",
                 position: 20, published_date: Date.new(2026, 6, 1), starred: true)
  end
  let!(:dropped) do
    Post.create!(title: "drop me", body: "drop body", status: "draft",
                 position: 1, published_date: Date.new(2020, 1, 1), starred: false)
  end

  def query_of(url)
    Rack::Utils.parse_nested_query(URI.parse(url).query.to_s)
  end

  it "applies beside the filters the request carries, in one hop" do
    visit "/admin/required_posts?q%5Btitle_cont%5D=me"

    expect(query_of(page.current_url)["q"])
      .to eq("title_cont" => "me", "status_eq" => "published")
    expect(page).to have_content("keep me")
    expect(page).to have_no_content("drop me")
  end

  it "applies even to a blank filters-form submission" do
    # A required window has no 'show me everything' escape - that is what required means.
    visit "/admin/required_posts?commit=Filter"

    expect(query_of(page.current_url)["q"]).to eq("status_eq" => "published")
    expect(page).to have_no_content("drop me")
  end

  it "keeps the admin's own value for the required filter" do
    visit "/admin/required_posts?q%5Bstatus_eq%5D=draft"

    expect(query_of(page.current_url)["q"]).to eq("status_eq" => "draft")
    expect(page).to have_content("drop me")
    expect(page).to have_no_content("keep me")
  end

  it "steps aside for a search that names a unique record" do
    visit "/admin/required_posts?q%5Bid_eq%5D=#{dropped.id}"

    expect(URI.parse(page.current_url).query).to eq("q%5Bid_eq%5D=#{dropped.id}")
    expect(page).to have_content("drop me")
    expect(page).to have_no_content("keep me")
  end

  it "keeps required: away from the rendered input" do
    # required: is also a Formtastic option: leaked through the merged-flat policy keys it
    # would mark the sidebar input HTML-required and block blank form submits in the browser.
    visit "/admin/required_posts"

    expect(page).to have_css("#filters_sidebar_section")
    expect(page).to have_no_css("#filters_sidebar_section [required]", visible: :all)
  end

  it "greets the imposed window with the notice" do
    visit "/admin/required_posts?q%5Btitle_cont%5D=me"

    expect(page).to have_content("Showing published posts by default")
  end

  describe "required: { if: }" do
    it "imposes the window beside its trigger keys" do
      visit "/admin/pinned_window_posts?q%5Btitle_cont%5D=me"

      expect(query_of(page.current_url)["q"])
        .to eq("title_cont" => "me", "status_eq" => "published")
      expect(page).to have_no_content("drop me")
    end

    it "stays home beside any other filter" do
      visit "/admin/pinned_window_posts?q%5Bposition_eq%5D=1"

      expect(query_of(page.current_url)["q"]).to eq("position_eq" => "1")
      expect(page).to have_content("drop me")
    end

    it "still applies as a plain default to the bare index" do
      visit "/admin/pinned_window_posts"

      expect(query_of(page.current_url)["q"]).to eq("status_eq" => "published")
    end
  end

  it "raises for required: with an unknown option" do
    expect { visit "/admin/banana_required_option_posts?q%5Btitle_cont%5D=x" }
      .to raise_error(ArgumentError, /required:.*takes true or/m)
  end

  it "raises for required: with no default: to fall back on" do
    expect { visit "/admin/required_banana_posts" }
      .to raise_error(ArgumentError, /title_cont.*required.*no default/m)
  end

  it "counts any of the filter's own keys as answering the group" do
    # An endless default fills only the gteq slot, but an upper-only request still answered
    # THIS filter - injecting the default lower bound beside it would execute a pair the
    # admin never meant.
    visit "/admin/required_open_posts?q%5Bpublished_date_lteq%5D=2026-06-30"

    expect(query_of(page.current_url)["q"]).to eq("published_date_lteq" => "2026-06-30")
    expect(page).to have_content("keep me")
    expect(page).to have_content("drop me")
  end

  it "treats an array of blanks as unanswered" do
    # ?q[k][]= survives a naive blank check ([""].blank? is false) while Ransack discards
    # the condition - an unanswered window wearing an answered-looking URL.
    visit "/admin/required_posts?q%5Bstatus_eq%5D%5B%5D=&q%5Btitle_cont%5D=me"

    expect(query_of(page.current_url)["q"])
      .to eq("title_cont" => "me", "status_eq" => "published")
    expect(page).to have_no_content("drop me")
  end

  it "treats blank-valued keys as unanswered" do
    # ?q[status_eq]= must not defeat the window: a blank clobbering the default and Ransack
    # then stripping the blank is a full-table scan wearing an answered-looking URL.
    visit "/admin/required_posts?q%5Bstatus_eq%5D=&q%5Btitle_cont%5D=me"

    expect(query_of(page.current_url)["q"])
      .to eq("title_cont" => "me", "status_eq" => "published")
    expect(page).to have_no_content("drop me")
    expect(page).to have_content("Showing published posts by default")
  end
end
