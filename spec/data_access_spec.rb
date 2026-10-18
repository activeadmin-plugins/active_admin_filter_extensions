# frozen_string_literal: true

require "spec_helper"

RSpec.describe ActiveAdminFilterExtensions::DataAccess do
  subject(:searched_with) do
    chain = FakeChain.new
    controller.send(:apply_filtering, chain)
    chain.ransacked_with
  end

  let(:controller) { FakeController.new(params: params, filters: filters) }
  let(:params) { {} }

  describe "a scalar default" do
    let(:filters) { { starred_eq: { extensions: { default: true } } } }

    it "applies to the filter name as it stands" do
      expect(searched_with).to eq("starred_eq" => true)
    end

    context "when the request carries filters of its own" do
      let(:params) { { q: { "title_cont" => "hello" } } }

      it "is left out" do
        expect(searched_with).to eq("title_cont" => "hello")
      end
    end

    context "when the filters form was submitted with every field blank" do
      # Active Admin disables empty fields on submit, so a blank submission sends no `q` at all
      # and is only distinguishable from a first visit by `commit`.
      let(:params) { { commit: "Filter" } }

      it "is not re-applied, so the admin sees everything" do
        expect(searched_with).to eq({})
      end
    end
  end

  describe "a q that is not a Hash" do
    let(:filters) { { starred_eq: { extensions: { default: true } } } }

    # Rack parses `?q=` to an empty String. It is blank, so the defaults apply - and merging
    # them with a String must not be attempted.
    context "when the request carries `?q=`" do
      let(:params) { { q: "" } }

      it "treats it as absent and applies the defaults" do
        expect(searched_with).to eq("starred_eq" => true)
      end
    end
  end

  describe "a Hash default" do
    let(:filters) { { created_at: { as: :date_range, extensions: { default: { gteq: "2020-01-01" } } } } }

    it "keys each value by its predicate" do
      expect(searched_with).to eq("created_at_gteq" => "2020-01-01")
    end
  end

  describe "an Array default" do
    # `filter :author, as: :check_boxes` submits as `q[author_id_in][]`, so the predicate side
    # of the key is `id_in`, not `in`.
    let(:filters) { { author: { as: :check_boxes, extensions: { default: { id_in: [1, 2] } } } } }

    it "is keyed the way the input submits it" do
      expect(searched_with).to eq("author_id_in" => [1, 2])
    end
  end

  describe "a Proc default" do
    let(:filters) { { position_eq: { extensions: { default: -> { params[:seed] } } } } }
    let(:params) { { seed: "7" } }

    it "is evaluated against the controller" do
      expect(searched_with).to eq("position_eq" => "7")
    end

    context "when it returns nil" do
      let(:params) { {} }

      it "applies no filter rather than filtering on NULL" do
        expect(searched_with).to eq({})
      end
    end

    it "is evaluated once per request, so it may query" do
      calls = 0
      controller = FakeController.new(filters: { title_eq: { extensions: { default: -> { calls += 1; "v" } } } })
      3.times { controller.send(:filter_default_values) }
      expect(calls).to eq(1)
    end
  end

  describe "a Symbol default" do
    let(:filters) { { title_eq: { extensions: { default: :hello } } } }

    it "is a value, not a method to send" do
      expect(searched_with).to eq("title_eq" => :hello)
    end
  end

  describe ":if and :unless" do
    let(:filters) do
      {
        starred_eq: { extensions: { default: true }, if: -> { false } },
        position_eq: { extensions: { default: 1 }, unless: -> { true } },
        title_eq: { extensions: { default: "kept" }, if: -> { true } }
      }
    end

    it "only applies the defaults of the filters that are rendered" do
      expect(searched_with).to eq("title_eq" => "kept")
    end

    it "accepts a Symbol condition and sends it to the controller" do
      controller = FakeController.new(filters: { title_eq: { extensions: { default: "v" }, if: :never } })
      def controller.never = false
      expect(controller.send(:filter_default_values)).to eq({})
    end
  end

  describe "#filter_defaults_apply?" do
    let(:filters) { { starred_eq: { extensions: { default: true } } } }

    context "when an override lets defaults through on a partly filtered request" do
      let(:params) { { q: { "customer_id_eq" => "7" } } }

      before do
        def controller.filter_defaults_apply?
          super || params[:q].keys == %w[customer_id_eq]
        end
      end

      it "keeps what the request asked for and adds the defaults to it" do
        expect(searched_with).to eq("customer_id_eq" => "7", "starred_eq" => true)
      end
    end

    context "when the request carries a value for a filter that also declares a default" do
      let(:params) { { q: { "starred_eq" => false } } }

      before do
        def controller.filter_defaults_apply? = true
      end

      it "leaves the request value alone rather than overwriting it" do
        expect(searched_with).to eq("starred_eq" => false)
      end
    end
  end

  describe "a resource without any default" do
    let(:filters) { { title: {} } }

    it "leaves the request alone" do
      expect(searched_with).to eq({})
    end
  end

end
