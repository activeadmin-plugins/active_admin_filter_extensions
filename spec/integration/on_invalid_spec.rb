# frozen_string_literal: true

require "rails_helper"
require "rack/utils"

# The edges of :reset and of the redirect's value rewriting.
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
