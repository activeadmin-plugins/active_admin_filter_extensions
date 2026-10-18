# frozen_string_literal: true

require "rails_helper"
require "rack/utils"

# The gem's defining behavior: the bare index redirects once to itself with the effective
# filters spelled out in the query string. What the admin copies out of the address bar is
# then the page they were looking at - same window, same values - instead of a bare path that
# every recipient resolves against their own clock and their own preferences.
RSpec.describe "The redirect", type: :feature do
  before do
    Post.create!(title: "keep me", body: "keep body", status: "published",
                 position: 20, published_date: Date.new(2026, 6, 1), starred: true)
    Post.create!(title: "drop me", body: "drop body", status: "draft",
                 position: 1, published_date: Date.new(2020, 1, 1), starred: false)
  end

  def query_of(url)
    Rack::Utils.parse_nested_query(URI.parse(url).query.to_s)
  end

  describe "a bare visit" do
    it "lands on a URL that carries the defaults, values frozen" do
      visit "/admin/posts"

      expect(query_of(page.current_url)["q"])
        .to eq("status_eq" => "published", "published_date_gteq" => "2026-01-01")
      expect(page).to have_content("keep me")
      expect(page).to have_no_content("drop me")
    end

    it "keeps the rest of the query string" do
      visit "/admin/posts?order=title_asc&page=1"

      expect(query_of(page.current_url)).to include("order" => "title_asc", "page" => "1")
      expect(query_of(page.current_url)["q"]).to include("status_eq" => "published")
    end
  end

  describe "a widened filter_defaults_apply?" do
    it "adds the defaults beside the pinned key in one hop" do
      visit "/admin/widened_posts?q%5Btitle_cont%5D=keep"

      expect(query_of(page.current_url)["q"])
        .to eq("title_cont" => "keep", "status_eq" => "published")
      expect(page).to have_content("keep me")
      expect(page).to have_no_content("drop me")

      # The redirected-to URL itself passes through - the guard has converged.
      converged = page.current_url
      visit converged
      expect(page.current_url).to eq(converged)
    end
  end

  it "treats `?q=` - an empty string - as a bare visit" do
    visit "/admin/posts?q="

    expect(query_of(page.current_url)["q"]).to include("status_eq" => "published")
    expect(page).to have_no_content("drop me")
  end

  describe "a request that already says what it wants" do
    it "is left alone when it carries its own filters" do
      visit "/admin/posts?q%5Bstatus_eq%5D=draft"

      expect(query_of(page.current_url)["q"]).to eq("status_eq" => "draft")
      expect(page).to have_content("drop me")
      expect(page).to have_no_content("keep me")
    end

    it "is left alone after a blank filters-form submission" do
      # Submitting the form with every field blank sends `commit` and no `q` - the admin asked
      # for everything, and a redirect back to the defaults would make that impossible to ask.
      visit "/admin/posts?commit=Filter"

      expect(query_of(page.current_url)).to eq("commit" => "Filter")
      expect(page).to have_content("keep me")
      expect(page).to have_content("drop me")
    end
  end

  # The URL is only rewritten where an address bar is watching. The defaults still filter a
  # CSV export - that is the gem's core, not the mode's - so skipping the redirect loses
  # nothing but the detour.
  it "exports CSV in one request, defaults still applied" do
    visit "/admin/posts.csv"

    expect(URI.parse(page.current_url).query).to be_nil
    expect(page.body).to include("keep me")
    expect(page.body).not_to include("drop me")
  end

  it "does not chase a default the URL cannot carry" do
    # to_query drops an empty Array entirely, so redirecting on it would loop: the redirected
    # URL parses back without the key and the next request is bare again. Such a value stays
    # out of the URL instead.
    visit "/admin/empty_default_posts"

    expect(URI.parse(page.current_url).query).to be_nil
    expect(page).to have_content("keep me")
    expect(page).to have_content("drop me")
  end

  it "does not chase a blank default the URL cannot round-trip" do
    # ?q[k]= comes back in with the blank stripped - chasing it alternates between the blank
    # URL and the bare one forever.
    visit "/admin/banana_blank_default_posts"

    expect(URI.parse(page.current_url).query).to be_nil
    expect(page).to have_content("keep me")
    expect(page).to have_content("drop me")
  end

  it "does not chase an Array default whose members are all blank" do
    # [nil] survives a plain blank-reject, serializes to ?q[k][]= and parses back as [""] -
    # which normalization drops, so the defaults re-apply and the two sides never agree.
    visit "/admin/nil_member_default_posts"

    expect(URI.parse(page.current_url).query).to be_nil
    expect(page).to have_content("keep me")
    expect(page).to have_content("drop me")
  end

  it "does not redirect a resource that declares no defaults" do
    visit "/admin/no_defaults_posts"

    expect(URI.parse(page.current_url).query).to be_nil
    expect(page).to have_content("keep me")
    expect(page).to have_content("drop me")
  end

  # A batch action flashes and redirects back to the index; the bare index then answers 302
  # again. Flash survives exactly one request, so without keeping it the extra hop eats every
  # such message.
  it "keeps a flash that arrived from another action across the extra hop" do
    visit "/admin/posts/poke"

    expect(query_of(page.current_url)["q"]).to include("status_eq" => "published")
    expect(page).to have_content("poked")
  end

  # Without this the redirect would silently eat every notice: the flash is set on the request
  # the defaults apply to, and that is the one that answers 302 - so it has to travel.
  describe "a declared default_filters_notice" do
    it "survives the redirect" do
      visit "/admin/notice_posts"

      expect(query_of(page.current_url)["q"]).to eq("status_eq" => "published")
      expect(page).to have_content("Showing published posts by default")
    end

    it "does not eat a flash that arrived from another action" do
      # Writing the notice loads the flash, and a loaded flash sweeps what came in with the
      # request when it commits - here, on a 302 that renders nothing. The redirect keeps the
      # arriving entries, so a batch action's message and the notice land together.
      visit "/admin/notice_posts/poke"

      expect(query_of(page.current_url)["q"]).to eq("status_eq" => "published")
      expect(page).to have_content("poked")
      expect(page).to have_content("Showing published posts by default")
    end

    it "yields its shared flash key to a message that arrived from another action" do
      # On the default :notice key the notice and a batch action's message collide; the
      # arriving one names what just happened, so it is the one the admin must see.
      visit "/admin/colliding_notice_posts/poke"

      expect(page).to have_content("poked")
    end

    it "still greets a bare visit on its default flash key" do
      visit "/admin/colliding_notice_posts"

      expect(page).to have_content("Showing published posts by default")
    end

    it "stays quiet on a widened request that overrode every default" do
      # filter_defaults_apply? says yes, but the request answered every defaulted key itself -
      # no default reached the search, and the notice must not claim otherwise.
      visit "/admin/widened_notice_posts?q%5Bstatus_eq%5D=draft&q%5Btitle_cont%5D=drop"

      expect(page).to have_content("drop me")
      expect(page).to have_no_content("Showing published posts by default")
    end

    it "greets a widened request the defaults actually reached" do
      visit "/admin/widened_notice_posts?q%5Btitle_cont%5D=keep"

      expect(query_of(page.current_url)["q"])
        .to eq("title_cont" => "keep", "status_eq" => "published")
      expect(page).to have_content("Showing published posts by default")
    end

    it "does not greet a URL that already says what it shows" do
      # The redirected-to URL opened directly - a pasted link. The recipient asked for exactly
      # what the address says, so there is nothing to explain.
      visit "/admin/notice_posts?q%5Bstatus_eq%5D=published"

      expect(page).to have_no_content("Showing published posts by default")
    end
  end

end
