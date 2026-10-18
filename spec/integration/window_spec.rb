# frozen_string_literal: true

require "rails_helper"
require "rack/utils"

# `max_range:` and `min:` on a two-ended filter - the 90-day caps and retention floors three
# of the four inventoried apps hand-rolled. A violation resets the PAIR: both bounds dropped,
# one error flashed, the declared default refills.
RSpec.describe "Window policies: max_range and min", type: :feature do
  before do
    Post.create!(title: "keep me", body: "keep body", status: "published",
                 position: 20, published_date: Date.new(2026, 6, 1), starred: true)
    Post.create!(title: "drop me", body: "drop body", status: "draft",
                 position: 1, published_date: Date.new(2020, 1, 1), starred: false)
  end

  def query_of(url)
    Rack::Utils.parse_nested_query(URI.parse(url).query.to_s)
  end

  def visit_window(gteq: nil, lteq: nil)
    q = {}
    q["q[published_date_gteq]"] = gteq if gteq
    q["q[published_date_lteq]"] = lteq if lteq
    visit "/admin/window_posts?#{Rack::Utils.build_query(q)}"
  end

  it "refuses a range wider than max_range and falls back to the default" do
    visit_window(gteq: "2020-07-01", lteq: "2026-06-30")

    expect(page).to have_content("allows a maximum date range of 90 days")
    expect(query_of(page.current_url)["q"])
      .to eq("published_date_gteq" => "2026-05-01", "published_date_lteq" => "2026-06-30")
    expect(page).to have_content("keep me")
    expect(page).to have_no_content("Showing the default window")
  end

  it "refuses an inverted range" do
    visit_window(gteq: "2026-06-10", lteq: "2026-06-01")

    expect(page).to have_content("invalid date range value")
    expect(query_of(page.current_url)["q"])
      .to eq("published_date_gteq" => "2026-05-01", "published_date_lteq" => "2026-06-30")
  end

  it "keeps a range exactly as wide as the cap" do
    # Pins > (not >=): under a gem regression both suites would stay green while the
    # inclusive boundary silently flipped.
    visit_window(gteq: "2026-03-01", lteq: "2026-05-30")

    expect(query_of(page.current_url)["q"])
      .to eq("published_date_gteq" => "2026-03-01", "published_date_lteq" => "2026-05-30")
    expect(page).to have_no_content("maximum date range")
  end

  it "refuses an upper bound alone under a lone min: floor" do
    # No lower bound means everything before the retention floor - refused and reset even
    # when no max_range: is declared beside the floor.
    visit "/admin/floor_posts?q%5Bpublished_date_lteq%5D=2026-06-30"

    expect(page).to have_content("Published date: starts no earlier than 2020-06-01 (retention).")
    expect(query_of(page.current_url)["q"])
      .to eq("published_date_gteq" => "2026-05-01", "published_date_lteq" => "2026-06-30")
  end

  it "resets the whole pair when a value policy rejects one bound" do
    # Half the admin's window completed from the default pair is a window nobody asked for
    # and nothing validated - the CSV would execute it without the HTML's healing hop.
    recent = (Date.current - 30).strftime("%Y-%m-%d")
    visit "/admin/validated_window_posts.csv?q%5Bpublished_date_gteq%5D=#{recent}" \
          "&q%5Bpublished_date_lteq%5D=2026-07-01X"

    expect(page.body).to include("keep me")
  end

  it "raises for a default whose sanitizer widens it past its own cap" do
    # The window is judged on what is actually stored - after the sanitizer, not before.
    expect { visit "/admin/banana_sanitized_window_posts" }
      .to raise_error(ArgumentError, /violates its own window policy/)
  end

  it "refuses a bound that is not a plain string" do
    # ?q[..._gteq][]=date parses as a date via Array#to_s, then Ransack silently drops the
    # wrapped condition - an in-cap-looking URL running the unbounded scan the cap refuses.
    visit "/admin/window_posts?q%5Bpublished_date_gteq%5D%5B%5D=2026-06-01"

    expect(page).to have_content("invalid date range value")
    expect(query_of(page.current_url)["q"])
      .to eq("published_date_gteq" => "2026-05-01", "published_date_lteq" => "2026-06-30")
  end

  it "refuses an unparseable bound" do
    visit_window(gteq: "garbage", lteq: "2026-06-01")

    expect(page).to have_content("invalid date range value")
    expect(query_of(page.current_url)["q"])
      .to eq("published_date_gteq" => "2026-05-01", "published_date_lteq" => "2026-06-30")
  end

  it "refuses an upper bound alone" do
    # An upper bound alone is an infinitely wide window - the outage query the cap refuses.
    visit_window(lteq: "2026-06-30")

    expect(page).to have_content("allows a maximum date range of 90 days")
    expect(query_of(page.current_url)["q"])
      .to eq("published_date_gteq" => "2026-05-01", "published_date_lteq" => "2026-06-30")
  end

  it "refuses a bound before the min: floor, in the application's own words" do
    # The message comes from the app's locale file overriding the gem key - the i18n seam.
    visit_window(gteq: "2020-01-01", lteq: "2020-03-01")

    expect(page).to have_content("Published date: starts no earlier than 2020-06-01 (retention).")
    expect(query_of(page.current_url)["q"])
      .to eq("published_date_gteq" => "2026-05-01", "published_date_lteq" => "2026-06-30")
  end

  it "treats a lower bound left open as unbounded" do
    # An upper bound alone is an infinitely wide window - on the partitioned tables this
    # feature targets, that is the outage query the cap exists to refuse.
    visit_window(lteq: "2026-06-30")

    expect(page).to have_content("allows a maximum date range of 90 days")
    expect(query_of(page.current_url)["q"])
      .to eq("published_date_gteq" => "2026-05-01", "published_date_lteq" => "2026-06-30")
  end

  it "measures an open upper bound against now" do
    visit_window(gteq: "2020-07-01")

    expect(page).to have_content("allows a maximum date range of 90 days")
  end

  it "lets a future lower bound with no upper bound through" do
    # It selects a not-yet-written window - nothing to cap. (A hard loop in one of the apps
    # came from measuring exactly this against Time.current.) Computed, not a literal: a
    # hardcoded year goes red the day the clock catches up with it.
    future = (Date.current + 60).strftime("%Y-%m-%d")
    visit_window(gteq: future)

    expect(page).to have_no_content("allows a maximum date range")
    expect(query_of(page.current_url)["q"]).to eq("published_date_gteq" => future)
    expect(page).to have_no_content("keep me")
  end

  it "keeps a range inside every limit untouched" do
    visit_window(gteq: "2026-05-01", lteq: "2026-06-30")

    expect(query_of(page.current_url)["q"])
      .to eq("published_date_gteq" => "2026-05-01", "published_date_lteq" => "2026-06-30")
    expect(page).to have_content("keep me")
    expect(page).to have_no_content("invalid date range")
  end

  it "raises for a beginless default under max_range:" do
    # Unbounded below the cap: accepted, it would run the over-cap scan on every bare visit.
    # The bound must land in the lteq slot to be judged.
    expect { visit "/admin/banana_beginless_window_posts" }
      .to raise_error(ArgumentError, /violates its own window policy/)
  end

  it "raises when the fallback default itself violates the policy" do
    # Resetting into a default the policy would refuse again is a loop, not a fallback -
    # that is a configuration error and says so loudly.
    expect { visit "/admin/banana_window_posts?q%5Bpublished_date_gteq%5D=2020-07-01" }
      .to raise_error(ArgumentError, /default.*violates its own/m)
  end

  describe "the floor across time zones" do
    # Date#to_time speaks the SERVER zone while the bounds are parsed in Time.zone; with the
    # two apart, a bound exactly on the floor date was spuriously rejected (or genuinely
    # earlier ones silently passed, offset depending).
    around do |example|
      old_tz = ENV["TZ"]
      ENV["TZ"] = "America/New_York"
      example.run
    ensure
      ENV["TZ"] = old_tz
    end

    it "accepts a bound exactly on the floor whatever the server zone" do
      visit_window(gteq: "2020-06-01", lteq: "2020-06-20")

      expect(page).to have_no_content("cannot start before")
      expect(query_of(page.current_url)["q"])
        .to eq("published_date_gteq" => "2020-06-01", "published_date_lteq" => "2020-06-20")
    end
  end
end
