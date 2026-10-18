# frozen_string_literal: true

require "rails_helper"
require "rack/utils"

# `sanitize:` and `validate:` on a filter: value policies that used to live in hand-written
# before_actions. On violation the default policy is :reset - drop the offending key, flash
# the message, and let the declared default refill, with the redirect telling the truth about
# what actually ran.
RSpec.describe "Filter value policies", type: :feature do
  before do
    Post.create!(title: "keep me", body: "keep body", status: "published",
                 position: 20, published_date: Date.new(2026, 6, 1), starred: true)
    Post.create!(title: "drop me", body: "drop body", status: "draft",
                 position: 1, published_date: Date.new(2020, 1, 1), starred: false)
  end

  def query_of(url)
    Rack::Utils.parse_nested_query(URI.parse(url).query.to_s)
  end

  describe "sanitize:" do
    it "rewrites the value before the search sees it" do
      visit "/admin/guarded_posts?q%5Btitle_cont%5D=ke-ep"

      expect(page).to have_content("keep me")
      expect(page).to have_no_content("drop me")
    end

    it "sanitizes a frozen default without mutating the config" do
      visit "/admin/frozen_default_posts"

      expect(query_of(page.current_url)["q"]).to eq("title_cont" => "keep")
      expect(page).to have_content("keep me")
    end
  end

  describe "validate: with the default :reset policy" do
    it "drops the value, says why, and falls back to the declared default" do
      visit "/admin/guarded_posts?q%5Btitle_cont%5D=keep123"

      expect(page).to have_content("Title filter must not contain digits.")
      # The default refilled - and the URL says so: validation ran before the redirect
      # decision, so the address bar reflects what was actually searched.
      expect(query_of(page.current_url)["q"]).to eq("title_cont" => "keep")
      expect(page).to have_content("keep me")
      expect(page).to have_no_content("drop me")
    end

    it "does not greet the fallback with the defaults notice" do
      # One render, one message: the error already explains why the page shows the
      # default slice - the notice on top of it would be noise.
      visit "/admin/guarded_posts?q%5Btitle_cont%5D=keep123"

      expect(page).to have_no_content("Showing kept posts by default")
    end


    it "refills the default on a real filters-form submission too" do
      # The form always sends commit; the reset's whole promise is the refill, and a promise
      # that holds only on hand-typed URLs is not one.
      visit "/admin/guarded_posts?q%5Btitle_cont%5D=keep123&commit=Filter"

      expect(page).to have_content("Title filter must not contain digits.")
      expect(query_of(page.current_url)["q"]).to eq("title_cont" => "keep")
      expect(page).to have_no_content("drop me")
    end


    it "refuses a value that is not a plain string" do
      # Ransack executes ?q[title_cont][value]=x byte-identically to the scalar - skipping
      # the policy for non-String shapes was a straight bypass.
      visit "/admin/guarded_posts?q%5Btitle_cont%5D%5Bvalue%5D=keep123"

      expect(page).to have_content("filter has an invalid value")
      expect(query_of(page.current_url)["q"]).to eq("title_cont" => "keep")
    end

    it "leaves a valid value alone" do
      visit "/admin/guarded_posts?q%5Btitle_cont%5D=drop"

      expect(page).to have_no_content("Title filter must not contain digits.")
      expect(query_of(page.current_url)["q"]).to eq("title_cont" => "drop")
      expect(page).to have_content("drop me")
      expect(page).to have_no_content("keep me")
    end

    it "still greets a bare visit with the notice" do
      visit "/admin/guarded_posts"

      expect(page).to have_content("Showing kept posts by default")
      expect(page).to have_no_content("drop me")
    end
  end

  describe "message: overrides the violation text" do
    it "speaks the filter's own words for a built-in validator" do
      visit "/admin/ip_guarded_posts?q%5Btitle_cont%5D=not-an-ip"

      expect(page).to have_content("Allowed IP address is incorrect!")
      expect(page).to have_no_content("filter has an invalid value")
    end

    it "falls back to the generic message for a Symbol no locale defines" do
      visit "/admin/banana_message_posts?q%5Btitle_cont%5D=keep123"

      expect(page).to have_content("Title cont filter has an invalid value.")
      expect(page).to have_no_content("translation missing")
    end

    it "stays quiet for a valid value" do
      visit "/admin/ip_guarded_posts?q%5Btitle_cont%5D=10.0.0.0%2F8"

      expect(page).to have_no_content("Allowed IP address is incorrect!")
    end
  end
end
