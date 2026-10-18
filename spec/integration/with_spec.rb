# frozen_string_literal: true

require "rails_helper"
require "rack/utils"

# `with:` - a cross-filter group: either every key or none. Half a pair is reset to the
# declared defaults with a warning (the monthly-invoices year/month shape), whichever side
# the half came from.
RSpec.describe "with: filters", type: :feature do
  before do
    Post.create!(title: "keep me", body: "keep body", status: "published",
                 position: 20, published_date: Date.new(2026, 6, 1), starred: true)
    Post.create!(title: "drop me", body: "drop body", status: "draft",
                 position: 1, published_date: Date.new(2020, 1, 1), starred: false)
  end

  def query_of(url)
    Rack::Utils.parse_nested_query(URI.parse(url).query.to_s)
  end

  it "resets a half-answered group to the defaults, saying so" do
    visit "/admin/paired_posts?q%5Bstatus_eq%5D=draft"

    expect(page).to have_content("must be given together")
    expect(query_of(page.current_url)["q"])
      .to eq("status_eq" => "published", "starred_eq" => "true")
    expect(page).to have_content("keep me")
    expect(page).to have_no_content("drop me")
  end

  it "names the filters without their predicates, whatever the predicate" do
    # The old humanizer knew _eq/_in/_cont only; a _gteq pair flashed "Published date gteq".
    visit "/admin/paired_date_posts?q%5Bpublished_date_gteq%5D=2026-01-01"

    expect(page).to have_content("Position and Published date filters must be given together")
  end

  it "trips from the side that declared nothing" do
    # PairedDatePost declares with: only on published_date; the partner must trip the
    # same group.
    visit "/admin/paired_date_posts?q%5Bposition_eq%5D=1"

    expect(page).to have_content("must be given together")
    expect(URI.parse(page.current_url).query).to be_nil
  end

  it "warns once for mirrored declarations" do
    # PairedPost declares with: on both members - the two declarations are one group.
    visit "/admin/paired_posts?q%5Bstatus_eq%5D=draft"

    expect(page).to have_css(".flash_warning", count: 1)
  end

  it "does not count a blank-array partner as answered" do
    # q[partner][]= survives a raw present? check while normalization drops it - on the CSV,
    # which gets no canonicalizing hop, half the group would execute silently.
    visit "/admin/paired_posts.csv?q%5Bstatus_eq%5D=draft&q%5Bstarred_eq%5D%5B%5D="

    expect(page.body).to include("keep me")
    expect(page.body).not_to include("drop me")
  end

  it "lets a fully-answered group through" do
    visit "/admin/paired_posts?q%5Bstatus_eq%5D=draft&q%5Bstarred_eq%5D=false"

    expect(page).to have_no_content("must be given together")
    expect(page).to have_content("drop me")
    expect(page).to have_no_content("keep me")
  end

  it "treats overlapping groups as one question" do
    # [title,status] and [status,starred] share status: answering title+status must not
    # pass the first group and then have the second reset status out from under it - on the
    # CSV, which gets no second chance.
    visit "/admin/chained_pair_posts.csv?q%5Btitle_cont%5D=keep&q%5Bstatus_eq%5D=published"

    expect(page.body).to include("keep me")
    expect(page.body).to include("drop me")
  end

  it "pulls the partner's default along with a required refill" do
    # status is required-with-default and with: starred; starred defaults to false. The
    # refill must carry both, or the search runs the half-group enforcement never saw.
    visit "/admin/required_pair_posts.csv?q%5Btitle_cont%5D=keep"

    expect(page.body).not_to include("keep me")
    expect(page.body).not_to include("drop me")
  end

  it "carries the whole group through the redirect on a required refill" do
    visit "/admin/required_pair_posts?q%5Btitle_cont%5D=keep"

    expect(query_of(page.current_url)["q"])
      .to eq("title_cont" => "keep", "status_eq" => "published", "starred_eq" => "false")
  end

  it "raises when defaults answer only half the group" do
    # The fallback is held to the same all-or-none contract the enforcement imposes.
    expect { visit "/admin/banana_half_paired_posts" }
      .to raise_error(ArgumentError, /answer the whole\s+group or none/m)
  end

  it "says nothing on a bare visit" do
    visit "/admin/paired_posts"

    expect(page).to have_no_content("must be given together")
    expect(page).to have_content("keep me")
  end
end
