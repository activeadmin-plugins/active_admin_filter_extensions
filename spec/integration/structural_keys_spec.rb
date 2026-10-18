# frozen_string_literal: true

require "rails_helper"
require "rack/utils"

# Ransack reads more than conditions out of q: `m` switches the combinator to OR, `g` nests
# whole condition groups. No Active Admin filter form submits them, and everything here
# reasons about flat condition keys - so a structural key is not an answer, it is a bypass.
# They are stripped before anything reads the request.
RSpec.describe "structural Ransack keys", type: :feature do
  before do
    Post.create!(title: "keep me", body: "keep body", status: "published",
                 position: 20, published_date: Date.new(2026, 6, 1), starred: true)
    Post.create!(title: "drop me", body: "drop body", status: "draft",
                 position: 1, published_date: Date.new(2020, 1, 1), starred: false)
  end

  def query_of(url)
    Rack::Utils.parse_nested_query(URI.parse(url).query.to_s)
  end

  it "strips q[m]=or instead of letting it widen the search" do
    visit "/admin/posts?q%5Bm%5D=or" \
          "&q%5Bstatus_eq%5D=published&q%5Bpublished_date_gteq%5D=2026-01-01"

    expect(query_of(page.current_url)["q"])
      .to eq("status_eq" => "published", "published_date_gteq" => "2026-01-01")
    expect(page).to have_content("keep me")
    expect(page).to have_no_content("drop me")
  end

  it "strips the long-form aliases Ransack also answers to" do
    # `conditions` is `c` spelled out (as `sorts` is `s`) - the alias must not walk around
    # the strip, least of all on the CSV, which gets no canonicalizing hop.
    visit "/admin/string_posts.csv?q%5Bconditions%5D%5B0%5D%5Btitle_cont%5D=drop"

    expect(page.body).to include("keep me")
    expect(page.body).not_to include("drop me")
  end

  it "does not let a structural-only q suppress the defaults on CSV" do
    # The HTML path would self-heal with a hop; the CSV runs filtering_params directly, and
    # a q that holds nothing but structure is a bare request.
    visit "/admin/string_posts.csv?q%5Bg%5D%5B0%5D%5Btitle_cont%5D=drop"

    expect(page.body).to include("keep me")
    expect(page.body).not_to include("drop me")
  end

  it "strips q[g] groupings no one declared" do
    visit "/admin/posts?q%5Bg%5D%5B0%5D%5Btitle_cont%5D=drop"

    expect(query_of(page.current_url)["q"])
      .to eq("status_eq" => "published", "published_date_gteq" => "2026-01-01")
    expect(page).to have_no_content("drop me")
  end
end
