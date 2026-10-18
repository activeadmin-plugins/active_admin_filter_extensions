# frozen_string_literal: true

require "rails_helper"

# `require_any_filter` - an index that answers no question until it is asked one: a bare
# visit renders an empty collection with the notice instead of the whole table (or, in one
# inventoried case, instead of a silent model-level `return []`).
RSpec.describe "require_any_filter", type: :feature do
  before do
    Post.create!(title: "keep me", body: "keep body", status: "published",
                 position: 20, published_date: Date.new(2026, 6, 1), starred: true)
    Post.create!(title: "drop me", body: "drop body", status: "draft",
                 position: 1, published_date: Date.new(2020, 1, 1), starred: false)
  end

  it "renders nothing on a bare visit, and says why" do
    visit "/admin/picky_posts"

    expect(page).to have_content("You must specify at least one filter")
    expect(page).to have_no_content("keep me")
    expect(page).to have_no_content("drop me")
  end

  it "renders an empty result, not Active Admin's blank slate" do
    # The guard blanks the collection; with no `q` in the request Active Admin reads that as
    # "this table has no rows at all" and offers a Create link beside the warning.
    visit "/admin/picky_posts"

    expect(page).to have_content("No Picky Posts found")
    expect(page).to have_no_content("There are no Picky Posts yet")
    expect(page).to have_no_link("Create one")
  end

  it "answers once asked" do
    visit "/admin/picky_posts?q%5Btitle_cont%5D=keep"

    expect(page).to have_no_content("You must specify at least one filter")
    expect(page).to have_content("keep me")
  end

  it "treats a blank filters-form submission as still unasked" do
    visit "/admin/picky_posts?commit=Filter"

    expect(page).to have_content("You must specify at least one filter")
    expect(page).to have_no_content("keep me")
  end

  it "treats an array of blanks as unasked" do
    visit "/admin/picky_posts?q%5Bstatus_eq%5D%5B%5D="

    expect(page).to have_content("You must specify at least one filter")
    expect(page).to have_no_content("keep me")
  end

  it "treats a blank-valued filter as unasked" do
    visit "/admin/picky_posts?q%5Btitle_cont%5D="

    expect(page).to have_content("You must specify at least one filter")
    expect(page).to have_no_content("keep me")
  end

  it "treats a key no declared filter submits as unasked" do
    # Ransack silently ignores an unknown condition - junk, a stale bookmark after a filter
    # rename - so counting it as a question renders the unfiltered dump behind a valid-looking
    # URL.
    visit "/admin/picky_posts?q%5Bjunk%5D=1"

    expect(page).to have_content("You must specify at least one filter")
    expect(page).to have_no_content("keep me")
    expect(page).to have_no_content("drop me")
  end

  it "treats a predicate-less stem of a declared filter as unasked" do
    # q[title] stems to the declared title_cont, but Ransack ignores a key with no
    # predicate - counting it renders the unfiltered dump behind a plausible URL.
    visit "/admin/picky_posts?q%5Btitle%5D=keep"

    expect(page).to have_content("You must specify at least one filter")
    expect(page).to have_no_content("keep me")
  end

  it "counts a sibling predicate of a declared filter as asked" do
    visit "/admin/picky_posts?q%5Btitle_eq%5D=keep%20me"

    expect(page).to have_no_content("You must specify at least one filter")
    expect(page).to have_content("keep me")
  end

  it "falls back to the shipped text for a notice key no locale defines" do
    visit "/admin/banana_notice_key_posts"

    expect(page).to have_content("You must specify at least one filter")
    expect(page).to have_no_content("translation missing")
  end

  it "notices when a policy just reset the only question" do
    # The validator empties q; without re-checking afterwards the whole table renders with no
    # warning - the unfiltered dump the guard was declared to forbid.
    visit "/admin/picky_posts?q%5Btitle_cont%5D=zz9"

    expect(page).to have_content("You must specify at least one filter")
    expect(page).to have_no_content("keep me")
  end
end
