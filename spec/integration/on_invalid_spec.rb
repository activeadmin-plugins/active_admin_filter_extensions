# frozen_string_literal: true

require "rails_helper"
require "rack/utils"

# `on_invalid:` names what a violated policy does. :reset (the default) is covered elsewhere;
# here the other two: :reject bounces back, :empty shows nothing but says why.
RSpec.describe "on_invalid policies", type: :feature do
  before do
    Post.create!(title: "keep me", body: "keep body", status: "published",
                 position: 20, published_date: Date.new(2026, 6, 1), starred: true)
    Post.create!(title: "drop me", body: "drop body", status: "draft",
                 position: 1, published_date: Date.new(2020, 1, 1), starred: false)
  end

  def query_of(url)
    Rack::Utils.parse_nested_query(URI.parse(url).query.to_s)
  end

  describe ":reject" do
    it "flashes and bounces to the bare index" do
      visit "/admin/reject_posts?q%5Bposition_eq%5D=abc"

      expect(page).to have_content("Position filter has an invalid value.")
      expect(URI.parse(page.current_url).query).to be_nil
      expect(page).to have_content("keep me")
      expect(page).to have_content("drop me")
    end

    it "bounces once even when several filters are violated" do
      # redirect_back does not break Ruby loops; without a performed? guard the second
      # violation double-renders into a 500 instead of the promised bounce.
      visit "/admin/reject_posts?q%5Bposition_eq%5D=abc&q%5Btitle_cont%5D=keep123"

      expect(URI.parse(page.current_url).query).to be_nil
      expect(page).to have_content("filter has an invalid value.").or have_content("must not contain digits")
    end

    it "bounces to the bare index when back is the offending URL itself" do
      # Browsers keep the original Referer across a 302: redirect_back would re-reject the
      # same request forever, dying at the browser's redirect cap instead of showing the
      # error.
      offending = "/admin/reject_posts?q%5Bposition_eq%5D=abc"
      page.driver.header("Referer", "http://www.example.com#{offending}")
      visit offending

      expect(URI.parse(page.current_url).query).to be_nil
      expect(page).to have_content("Position filter has an invalid value.")
    ensure
      page.driver.header("Referer", nil)
    end

    it "degrades to :reset off the HTML path" do
      # A CSV index is answered in one request everywhere else in the gem, a flash it cannot
      # render would be lost, and url_for drops the format - so the export is bounded the
      # :reset way instead of being bounced into an HTML page.
      visit "/admin/reject_posts.csv?q%5Bposition_eq%5D=abc"

      expect(page.response_headers["Content-Type"]).to include("text/csv")
      expect(page.body).to include("keep me")
    end

    it "bounces once when value and window policies are violated together" do
      visit "/admin/reject_window_posts?q%5Bpublished_date_gteq%5D=2020-01-01X&q%5Bpublished_date_lteq%5D=2026-01-01X"

      expect(URI.parse(page.current_url).query).to be_nil
      expect(page).to have_content("No X dates.")
    end
  end

  describe ":empty" do
    it "shows nothing, says why, and keeps the admin's input on screen" do
      visit "/admin/empty_posts?q%5Btitle_cont%5D=keep123"

      expect(page).to have_content("Title filter must not contain digits.")
      expect(page).to have_no_content("keep me")
      expect(page).to have_no_content("drop me")
      expect(page).to have_field("q[title_cont]", with: "keep123")
      expect(URI.parse(page.current_url).query).to eq("q%5Btitle_cont%5D=keep123")
    end

    it "survives the canonicalizing redirect when the sanitizer empties the value" do
      # digits("abc") is "" - the blank would otherwise redirect away, and the next request,
      # flagless, renders the whole table.
      visit "/admin/empty_digits_posts?q%5Bposition_eq%5D=abc"

      expect(URI.parse(page.current_url).query).to eq("q%5Bposition_eq%5D=abc")
      expect(page).to have_content("filter has an invalid value")
      # The admin's own input is preserved (not the sanitizer's ""): the URL carries it and
      # the form re-renders it - as Ransack casts it for this integer attribute, so "0".
      # The literal-text case is EmptyPost's string-attribute example above.
      expect(page).to have_field("q[position_eq]", with: "0")
      expect(page).to have_no_content("keep me")
      expect(page).to have_no_content("drop me")
    end

    it "leaves a valid search alone" do
      visit "/admin/empty_posts?q%5Btitle_cont%5D=drop"

      expect(page).to have_content("drop me")
      expect(page).to have_no_content("keep me")
    end
  end

  describe "a default against its own value policy" do
    it "raises instead of flashing itself forever" do
      # Accepted, the default refills on every bare visit, fails its own validator, resets,
      # and refills - a permanent self-inflicted error banner.
      expect { visit "/admin/banana_validated_default_posts" }
        .to raise_error(ArgumentError, /default that violates its own validate/)
    end
  end

  describe "a default against its own value policy" do
    it "raises for a non-String default its validator refuses as submitted" do
      # The URL will say the default as a String - that is the value to judge.
      expect { visit "/admin/banana_integer_default_posts" }
        .to raise_error(ArgumentError, /default that violates its own validate/)
    end
  end

  describe "values the URL cannot carry" do
    it "raises for a sanitizer with no fixpoint instead of redirect-looping" do
      expect { visit "/admin/banana_sanitize_posts?q%5Btitle_cont%5D=acme" }
        .to raise_error(ArgumentError, /sanitize.*idempotent/m)
    end

    it "raises for a default its sanitizer keeps rewriting" do
      # The default faces the same fixpoint check submitted values do - otherwise the CSV
      # searches the once-sanitized value while the HTML converges on another.
      expect { visit "/admin/banana_shrinking_default_posts" }
        .to raise_error(ArgumentError, /sanitize.*idempotent/m)
    end

    it "raises for a sanitizer that mutates the value in place" do
      # `value << "%"` returns the SAME object - compared against itself, the no-fixpoint
      # guard would wave the loop through.
      expect { visit "/admin/banana_mutating_sanitize_posts?q%5Btitle_cont%5D=acme" }
        .to raise_error(ArgumentError, /sanitize.*idempotent/m)
    end

    it "does not chase a default that serializes to nothing" do
      # {}.to_query drops the pair entirely - same loop shape as the empty Array.
      visit "/admin/empty_hash_default_posts"

      expect(URI.parse(page.current_url).query).to be_nil
      expect(page).to have_content("keep me")
    end
  end

  describe "sanitize: rewrites the URL to what actually ran" do
    it "redirects once to the sanitized value, without greeting it as a default" do
      visit "/admin/guarded_posts?q%5Btitle_cont%5D=ke-ep"

      expect(query_of(page.current_url)["q"]).to eq("title_cont" => "keep")
      expect(page).to have_content("keep me")
      # The search ran the admin's own (sanitized) value - no default engaged, so the
      # travelling notice must stay home.
      expect(page).to have_no_content("Showing kept posts by default")
    end
  end
end
