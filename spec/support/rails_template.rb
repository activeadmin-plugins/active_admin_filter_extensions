# frozen_string_literal: true

# Rails template that builds the sample app the specs run against.

# Rails 8 no longer generates a Sprockets manifest, and Active Admin 3 needs one.
FileUtils.mkdir_p("app/assets/config")
File.write("app/assets/config/manifest.js", "//= link_tree ../images\n")

# One column per filter input type, so every input can be exercised against a real index.
generate :model,
         "post title:string body:text status:string position:integer " \
         "published_date:date starred:boolean --force"

inject_into_file "app/models/post.rb",
                 "  def self.ransackable_attributes(auth_object = nil)\n" \
                 "    %w[id title body status position published_date starred]\n" \
                 "  end\n" \
                 "  def self.ransackable_associations(auth_object = nil)\n" \
                 "    []\n" \
                 "  end\n",
                 after: "ApplicationRecord\n"

# Stands in for the signed-in admin carrying their own saved filter preset. Devise is out of the
# picture - the specs disable authentication - so `current_admin_user` is defined by hand below.
generate :model, "admin_user email:string default_status:string --force"

# Put the gem under test on the load path of the generated app.
gem_lib = File.expand_path(File.join(File.dirname(__FILE__), "..", "..", "lib"))
gsub_file "config/environment.rb",
          'require_relative "application"',
          "require_relative \"application\"\n" \
          "$LOAD_PATH.unshift('#{gem_lib}')\n" \
          "require \"active_admin_filter_extensions\"\n"

generate :"active_admin:install --skip-users"
generate :"formtastic:install"

file "config/initializers/current_admin_user.rb", <<~RUBY
  # No Devise here: the specs disable Active Admin authentication and this is all
  # `default: -> { current_admin_user... }` needs to resolve.
  ActiveAdmin.before_load do
    ActiveAdmin::BaseController.class_eval do
      def current_admin_user
        AdminUser.first
      end
      helper_method :current_admin_user
    end
  end
RUBY

# The sample app registers Post once per scenario - resources are cheap and a single index
# carrying every default at once would filter itself down to nothing.
file "app/admin/posts.rb", <<~RUBY
    ActiveAdmin.register Post do
      filter :status, as: :select, collection: %w[draft published], extensions: { default: "published" }
      filter :published_date, as: :date_range, extensions: { default: -> { Date.new(2026, 1, 1).. } }

      csv do
        column :title
      end

    # One registration per filter input type - separate resources, because a single index
    # carrying every default at once would filter itself down to nothing. Only a filter name
    # that already carries its predicate takes a scalar (ScalarPost); for everything else the
    # input decides the search key: `:numeric` submits `_eq`/`_gt`/`_lt`, `:date_range`
    # submits `_gteq` and `_lteq`, `:check_boxes` submits `_in[]`.
    ActiveAdmin.register Post, as: "StringPost" do
      filter :title, extensions: { default: "keep" }
    end

    ActiveAdmin.register Post, as: "ScalarPost" do
      filter :title_cont, as: :string, extensions: { default: "keep" }
    end

    ActiveAdmin.register Post, as: "NumericPost" do
      filter :position, as: :numeric, extensions: { default: { gt: 10 } }
    end

    ActiveAdmin.register Post, as: "DatePost" do
      filter :published_date, as: :date_range, extensions: { default: Date.new(2026, 1, 1).. }
    end

    ActiveAdmin.register Post, as: "SelectPost" do
      filter :status, as: :select, collection: %w[draft published], extensions: { default: "published" }
    end

    ActiveAdmin.register Post, as: "CheckBoxesPost" do
      filter :status, as: :check_boxes, collection: %w[draft published], extensions: { default: ["published"] }
    end

    ActiveAdmin.register Post, as: "BooleanPost" do
      filter :starred, extensions: { default: true }
    end

    ActiveAdmin.register Post, as: "AdminPreferencePost" do
      filter :status_eq, as: :select, collection: %w[draft published],
                         extensions: { default: -> { current_admin_user.default_status } }
    end

    ActiveAdmin.register Post, as: "ConditionalPost" do
      filter :title, extensions: { default: "keep" }, if: -> { false }
      filter :body, extensions: { default: "keep" }, unless: -> { true }
      filter :status, as: :select, collection: %w[draft published],
                      extensions: { default: "published" }, if: -> { true }
    end

    ActiveAdmin.register Post, as: "PlainPost" do
      filter :title
    end

    ActiveAdmin.register Post, as: "AmbiguousPost" do
      filter :published_date, as: :date_range, extensions: { default: Date.new(2026, 1, 1) }
    end

    ActiveAdmin.register Post, as: "ProcInputHtmlPost" do
      filter :status, as: :select, collection: %w[draft published],
                      input_html: proc { { class: "select2" } }, extensions: { default: "published" }
    end

    ActiveAdmin.register Post, as: "AllHiddenPost" do
      filter :title, if: -> { false }
    end


      # Stands in for any action that flashes and sends the admin back to the index - a batch
      # action, a callback - whose flash must survive the index's own redirect.
      collection_action :poke do
        redirect_to collection_path, notice: "poked"
      end
    end

    ActiveAdmin.register Post, as: "EmptyDefaultPost" do
      # A default that resolves to an empty Array - `-> { current_admin_user.visible_ids }` on an
      # admin with none - is a value to_query cannot carry into a URL.
      filter :position, as: :numeric, extensions: { default: { in: -> { [] } } }
    end

    ActiveAdmin.register Post, as: "BananaBlankDefaultPost" do
      # A blank default is a value ?q[k]= cannot round-trip (the blank is stripped on the way
      # back in) - it must stay out of the redirect, not loop it.
      filter :title_cont, as: :string, extensions: { default: "" }
    end

    ActiveAdmin.register Post, as: "WidenedPost" do
      filter :status, as: :select, collection: %w[draft published], extensions: { default: "published" }

      # The README's widening example: defaults still apply to a request that carries only its
      # pinned key. The redirect must add the default beside it - in ONE hop.
      controller do
        def filter_defaults_apply?
          super || params[:q].keys == %w[title_cont]
        end
      end
    end

    ActiveAdmin.register Post, as: "WidenedNoticePost" do
      default_filters_notice "Showing published posts by default"

      filter :title_cont, as: :string
      filter :status, as: :select, collection: %w[draft published], extensions: { default: "published" }

      # Widened: a status+title request still counts as one the defaults apply to - but the
      # notice must only speak when a default actually reached the search.
      controller do
        def filter_defaults_apply?
          super || (params[:q].keys - %w[status_eq title_cont]).empty?
        end
      end
    end

    ActiveAdmin.register Post, as: "GuardedPost" do
      default_filters_notice "Showing kept posts by default"

      # A value policy next to the default: strip what typing drags in, refuse what the
      # search cannot mean, and say so - the home-grown before_action guards, as options.
      filter :title_cont, as: :string,
                          extensions: { default: "keep",
                                    sanitize: ->(value) { value.delete("-") },
                                    validate: ->(value) { value.match?(/\\d/) && "Title filter must not contain digits." } }
    end

    ActiveAdmin.register Post, as: "RequiredPost" do
      default_filters_notice "Showing published posts by default"

      filter :id_eq, as: :string, label: "ID"
      filter :title_cont, as: :string
      # unless: - a search that names a unique record; the window steps aside for it.
      filter :status, as: :select, collection: %w[draft published],
                      extensions: { default: "published", required: { unless: %i[id_eq] } }
    end

    ActiveAdmin.register Post, as: "BananaRequiredOptionPost" do
      # An unknown required: option must raise, not silently mean true.
      filter :status, as: :select, collection: %w[draft published],
                      extensions: { default: "published", required: { iff: %i[title_cont] } }
      filter :title_cont, as: :string
    end

    ActiveAdmin.register Post, as: "PinnedWindowPost" do
      default_filters_notice "Showing published posts by default"

      filter :position
      filter :title_cont, as: :string
      # if: - the window matters only beside these keys; alone they scan too broadly.
      filter :status, as: :select, collection: %w[draft published],
                      extensions: { default: "published", required: { if: :title_cont } }
    end

    ActiveAdmin.register Post, as: "RequiredBananaPost" do
      # required with nothing to fall back on - the suite proves that raises.
      filter :title_cont, as: :string, extensions: { required: true }
    end

    ActiveAdmin.register Post, as: "RequiredOpenPost" do
      # A required window with an endless default: the group is answered by ANY of the
      # filter's own keys, not only the ones the default happens to fill.
      filter :published_date, as: :date_range,
                              extensions: { required: true, default: -> { Date.new(2026, 5, 1).. } }
    end

    ActiveAdmin.register Post, as: "BananaSanitizeBuiltinPost" do
      # An unknown built-in name must raise, not fall through to a controller method call.
      filter :title_cont, as: :string, extensions: { sanitize: :shout }
    end

    ActiveAdmin.register Post, as: "IntegerPost" do
      # The built-in numeric pair every app hand-rolled: strip to digits, refuse what does
      # not fit a PG int4.
      filter :position_eq, as: :string, extensions: { sanitize: :digits, validate: :integer }
    end

    ActiveAdmin.register Post, as: "DigitDefaultPost" do
      # The default is stored sanitized: what Ransack runs and what the URL says must be the
      # value the policy produced, on the first pass and on every format.
      filter :position_eq, as: :string, extensions: { default: "2-0a", sanitize: :digits, validate: :integer }
    end

    ActiveAdmin.register Post, as: "SignedDefaultPost" do
      # A non-String default still goes through the sanitizer, as the String the URL will
      # say - or the CSV and the HTML search different values.
      filter :position_eq, as: :string, extensions: { default: -20, sanitize: :digits, validate: :integer }
    end

    ActiveAdmin.register Post, as: "BananaIntegerDefaultPost" do
      # Its default is no String, but the URL will say it as one - validated as submitted.
      filter :position_eq, as: :string, extensions: { default: 2_147_483_648, validate: :integer }
    end

    ActiveAdmin.register Post, as: "BananaValidatedDefaultPost" do
      # Its default violates its own validate: - the suite proves that raises instead of
      # flashing itself on every bare visit, forever.
      filter :title_cont, as: :string,
                          extensions: { default: "v1",
                                    validate: ->(value) { value.match?(/\\d/) && "no digits" } }
    end

    ActiveAdmin.register Post, as: "BananaSanitizePost" do
      # Its sanitizer grows the value on every pass - the suite proves that raises instead of
      # redirect-looping forever.
      filter :title_cont, as: :string, extensions: { sanitize: ->(value) { "%\#{value}%" } }
    end

    ActiveAdmin.register Post, as: "BananaShrinkingDefaultPost" do
      # Its sanitizer trims one hyphen per pass - the default must face the same fixpoint
      # check submitted values do, or the formats search different values without a word.
      filter :title_cont, as: :string,
                          extensions: { default: "--keep",
                                        sanitize: ->(value) { value.sub(/\\A-/, "") } }
    end

    ActiveAdmin.register Post, as: "FrozenDefaultPost" do
      # A frozen default through an in-place sanitizer: the config's string is not the
      # sanitizer's to mutate - FrozenError on the first visit, or a quietly corrupted config.
      filter :title_cont, as: :string,
                          extensions: { default: "ke-ep".freeze,
                                        sanitize: ->(value) { value.delete!("-") || value } }
    end

    ActiveAdmin.register Post, as: "BananaMutatingSanitizePost" do
      # Its sanitizer rewrites the value IN PLACE and returns it - compared against itself,
      # the no-fixpoint guard would wave the loop through.
      filter :title_cont, as: :string, extensions: { sanitize: ->(value) { value << "%" } }
    end

    ActiveAdmin.register Post, as: "EmptyHashDefaultPost" do
      filter :status, as: :select, collection: %w[draft published],
                      extensions: { default: { in: -> { {} } } }
    end

    ActiveAdmin.register Post, as: "IpGuardedPost" do
      # The built-in validator with the app's own words - no lambda duplication just to keep a
      # legacy message.
      filter :title_cont, as: :string, extensions: { validate: :ip, message: "Allowed IP address is incorrect!" }
    end

    ActiveAdmin.register Post, as: "BananaMessagePost" do
      # Its validator answers a Symbol no locale defines - the generic message must speak,
      # not a translation-missing trace.
      filter :title_cont, as: :string,
                          extensions: { validate: ->(value) { value.match?(/\\d/) && :bogus_key } }
    end

    ActiveAdmin.register Post, as: "NoDefaultsPost" do
      filter :title
    end

    ActiveAdmin.register Post, as: "CollidingNoticePost" do
      # The notice on its DEFAULT flash key - the same :notice a batch action writes. Both have
      # to coexist on the redirect: the arriving message wins, it names what just happened.
      default_filters_notice "Showing published posts by default"

      filter :status, as: :select, collection: %w[draft published], extensions: { default: "published" }

      collection_action :poke do
        redirect_to collection_path, notice: "poked"
      end
    end

    ActiveAdmin.register Post, as: "NoticePost" do
      # Its own flash key, the way an app keeps the filters notice from colliding with the
      # :notice a batch action or callback writes - both have to survive the redirect together.
      default_filters_notice "Showing published posts by default", flash_key: :filters_notice

      filter :status, as: :select, collection: %w[draft published], extensions: { default: "published" }

      collection_action :poke do
        redirect_to collection_path, notice: "poked"
      end
    end
  RUBY

run "rm -rf test"
route "root to: 'admin/dashboard#index'"
rake "db:migrate"

# Removed last so the generators above still resolve their dependencies.
run "rm -f Gemfile Gemfile.lock"
