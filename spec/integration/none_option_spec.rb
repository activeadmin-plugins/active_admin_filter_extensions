# frozen_string_literal: true

require "rails_helper"
require "rack/utils"

# `none:` gives a select filter an option for the records whose attribute is empty - the one
# question no value of its collection can ask. The select submits a sentinel under its own key,
# and only the search is handed the `_null` condition it stands for.
RSpec.describe "the None option", type: :feature do
  let(:none) { ActiveAdminFilterExtensions.none_value }
  let(:aa_v4) { ActiveAdminFilterExtensions.aa_v4? }
  let!(:acme) { Account.create!(name: "Acme") }
  let!(:zenith) { Account.create!(name: "Zenith") }

  before do
    Post.create!(title: "acme post", status: "published", position: 20, account: acme)
    Post.create!(title: "zenith post", status: "draft", position: 1, account: zenith)
    Post.create!(title: "orphan post")
  end

  def query_of(url)
    Rack::Utils.parse_nested_query(URI.parse(url).query.to_s)
  end

  def options_of(name)
    page.all("select[name='#{name}'] option").map { |option| [option.text, option.value] }
  end

  # The entry of one search key in the Current Filters panel, which both moved and changed its
  # hook in Active Admin 4.
  def current_filter(key)
    if aa_v4
      "#active_search_sidebar_section li[data-filter='#{key}']"
    else
      "#search_status_sidebar_section li.current_filter_#{key}"
    end
  end

  it "renders first, after the blank option" do
    visit "/admin/none_posts"

    expect(options_of("q[account_id_eq]"))
      .to eq([["Any", ""], ["None", none], ["Acme", acme.id.to_s], ["Zenith", zenith.id.to_s]])
  end

  it "heads a multiple select, under the label the filter gave it" do
    visit "/admin/none_posts"

    expect(options_of("q[status_in][]"))
      .to eq([["No status", none], %w[draft draft], %w[published published]])
  end

  it "lists only the records with the attribute empty" do
    visit "/admin/none_posts"
    select "None", from: "q[account_id_eq]"
    click_button "Filter"

    expect(page).to have_content("orphan post")
    expect(page).to have_no_content("acme post")
    expect(page).to have_no_content("zenith post")
  end

  it "stays selected after the submit, under the key the select submitted" do
    # Ransack is handed account_id_null, so neither the search object nor a rewritten URL could
    # say which option was picked - the request, left as submitted, does.
    visit "/admin/none_posts"
    select "None", from: "q[account_id_eq]"
    click_button "Filter"

    expect(query_of(page.current_url)["q"]).to include("account_id_eq" => none)
    expect(page).to have_select("q[account_id_eq]", selected: "None")
  end

  it "returns the union for None beside a value on a multiple select" do
    visit "/admin/none_posts"
    select "No status", from: "q[status_in][]"
    select "draft", from: "q[status_in][]"
    click_button "Filter"

    expect(page).to have_content("orphan post")
    expect(page).to have_content("zenith post")
    expect(page).to have_no_content("acme post")
    expect(page).to have_select("q[status_in][]", selected: ["No status", "draft"])
  end

  it "searches None alone on a multiple select" do
    visit "/admin/none_posts?q%5Bstatus_in%5D%5B%5D=#{none}"

    expect(page).to have_content("orphan post")
    expect(page).to have_no_content("zenith post")
    expect(page).to have_select("q[status_in][]", selected: ["No status"])
  end

  it "filters the formats the redirect never touches" do
    visit "/admin/none_posts.csv?q%5Baccount_id_eq%5D=#{none}"

    expect(page).to have_content("orphan post")
    expect(page).to have_no_content("acme post")
  end

  it "raises for a filter that is not a select" do
    expect { visit "/admin/banana_none_posts" }
      .to raise_error(ArgumentError, /:title_cont declares none:.*needs a select that submits _eq or _in/m)
  end

  it "answers a required: filter" do
    # Left unanswered, the filter imposes its default beside the title...
    visit "/admin/required_none_posts?q%5Btitle_cont%5D=post"

    expect(query_of(page.current_url)["q"])
      .to eq("title_cont" => "post", "account_id_eq" => acme.id.to_s)

    # ...and "without an account" is an answer, not an absence to fill in.
    visit "/admin/required_none_posts?q%5Btitle_cont%5D=post&q%5Baccount_id_eq%5D=#{none}"

    expect(query_of(page.current_url)["q"]).to eq("title_cont" => "post", "account_id_eq" => none)
    expect(page).to have_content("orphan post")
    expect(page).to have_no_content("acme post")
  end

  it "can be the filter's default" do
    visit "/admin/default_none_posts"

    expect(query_of(page.current_url)["q"]).to eq("account_id_eq" => none)
    expect(page).to have_content("orphan post")
    expect(page).to have_no_content("acme post")
    expect(page).to have_select("q[account_id_eq]", selected: "None")
  end

  describe "beside value policies" do
    it "is not handed to validate:" do
      # :integer would refuse the sentinel and reset the filter to the whole table.
      visit "/admin/policed_none_posts?q%5Baccount_id_eq%5D=#{none}"

      expect(page).to have_no_content("Account filter has an invalid value.")
      expect(page).to have_content("orphan post")
      expect(page).to have_no_content("acme post")
    end

    it "is not handed to sanitize:, while the values beside it are" do
      # :digits would empty the sentinel; the URL keeps it and carries the cleaned value.
      visit "/admin/policed_none_posts?q%5Bposition_in%5D%5B%5D=#{none}&q%5Bposition_in%5D%5B%5D=2x0"

      expect(query_of(page.current_url)["q"]).to eq("position_in" => [none, "20"])
      expect(page).to have_content("orphan post")
      expect(page).to have_content("acme post")
      expect(page).to have_no_content("zenith post")
    end

    it "leaves every other value to the policy" do
      visit "/admin/policed_none_posts?q%5Baccount_id_eq%5D=abc"

      expect(page).to have_content("Account filter has an invalid value.")
    end
  end

  describe "in the Current Filters panel" do
    it "reads as the option, not as the condition it became" do
      # Left to Active Admin the `_null` condition reads "Account is null 1".
      visit "/admin/none_posts?q%5Baccount_id_eq%5D=#{none}"

      expect(page).to have_css(current_filter("account_id_null"), text: /Account equals\s*None/)
    end

    it "lists None beside the values chosen with it" do
      # Those sit in an OR grouping, which the panel does not list: left to Active Admin it
      # says nothing is filtered.
      visit "/admin/none_posts?q%5Bstatus_in%5D%5B%5D=#{none}&q%5Bstatus_in%5D%5B%5D=draft"

      expect(page).to have_css(current_filter("status_in"), text: /Status in\s*No status and draft/)
    end
  end
end
