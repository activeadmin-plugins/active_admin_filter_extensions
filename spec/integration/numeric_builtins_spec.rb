# frozen_string_literal: true

require "rails_helper"
require "rack/utils"

# The built-in numeric pair: `sanitize: :digits` strips a value to its digits, `validate:
# :integer` refuses what does not fit a PG int4 - the guard every inventoried app hand-rolled
# around its id/position filters.
RSpec.describe "built-in numeric policies", type: :feature do
  before do
    Post.create!(title: "keep me", body: "keep body", status: "published",
                 position: 20, published_date: Date.new(2026, 6, 1), starred: true)
    Post.create!(title: "drop me", body: "drop body", status: "draft",
                 position: 1, published_date: Date.new(2020, 1, 1), starred: false)
  end

  def query_of(url)
    Rack::Utils.parse_nested_query(URI.parse(url).query.to_s)
  end

  describe "validate: :integer" do
    it "refuses a value that does not fit a PG int4" do
      visit "/admin/integer_posts?q%5Bposition_eq%5D=2147483648"

      expect(page).to have_content("Position eq filter has an invalid value.")
      expect(URI.parse(page.current_url).query).to be_nil
    end

    it "lets the int4 maximum itself through" do
      visit "/admin/integer_posts?q%5Bposition_eq%5D=2147483647"

      expect(query_of(page.current_url)["q"]).to eq("position_eq" => "2147483647")
      expect(page).to have_no_content("invalid value")
    end
  end

  describe "a default through its own sanitizer" do
    it "stores and says the sanitized value on every format" do
      # Not only the HTML path (which would self-heal with an extra hop): the CSV runs
      # filtering_params directly and must search what the sanitizer produced.
      visit "/admin/digit_default_posts.csv"

      expect(page.body).to include("keep me")
      expect(page.body).not_to include("drop me")
    end

    it "sanitizes a non-String default the same way every format will see it" do
      visit "/admin/signed_default_posts.csv"

      expect(page.body).to include("keep me")
    end

    it "lands the sanitized default in the URL in one hop" do
      visit "/admin/digit_default_posts"

      expect(query_of(page.current_url)["q"]).to eq("position_eq" => "20")
      expect(page).to have_content("keep me")
    end
  end

  describe "sanitize: :digits" do
    it "strips the value to its digits and searches that" do
      visit "/admin/integer_posts?q%5Bposition_eq%5D=%202-0a"

      expect(query_of(page.current_url)["q"]).to eq("position_eq" => "20")
      expect(page).to have_content("keep me")
      expect(page).to have_no_content("drop me")
    end

    it "raises for an unknown built-in sanitizer" do
      expect { visit "/admin/banana_sanitize_builtin_posts?q%5Btitle_cont%5D=x" }
        .to raise_error(ArgumentError, /unknown built-in sanitizer/)
    end
  end
end
