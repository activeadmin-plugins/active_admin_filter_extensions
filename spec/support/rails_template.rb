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

file "config/locales/filter_extensions.en.yml", <<~YAML
  # Overrides one gem message the i18n way - the suite proves the seam.
  en:
    active_admin_filter_extensions:
      before_floor: "%{filter}: starts no earlier than %{floor} (retention)."
YAML

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

    ActiveAdmin.register Post, as: "PolicedBoxesPost" do
      # A multi-valued filter under a value policy: _in[] submits an Array of Strings, which
      # is the shape this input legitimately has - not a bypass.
      filter :status, as: :check_boxes, collection: %w[draft published],
                      extensions: { default: ["published"],
                                    validate: lambda { |value|
                                      next "Letters only." unless value.match?(/\\A[a-z]+\\z/)

                                      "No x statuses." if value.start_with?("x")
                                    } }
    end

    ActiveAdmin.register Post, as: "IntegerSanitizedBoxesPost" do
      filter :position, as: :check_boxes, collection: [1, 20],
                        extensions: { sanitize: ->(value) { Integer(value, 10).to_s }, validate: :integer }
    end

    ActiveAdmin.register Post, as: "NilMemberPolicedPost" do
      # An Array default with a blank member beside a real one - `[current_admin_user.team,
      # "published"]` for an admin with no team. The blank is not a value the request would
      # search, so it is not one the validator should judge.
      filter :status, as: :check_boxes, collection: %w[draft published],
                      extensions: { default: [nil, "published"],
                                    validate: lambda { |value|
                                      next "Letters only." unless value.match?(/\\A[a-z]+\\z/)

                                      "No x statuses." if value.start_with?("x")
                                    } }
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

    ActiveAdmin.register Post, as: "BananaExclusiveRangePost" do
      # The excluded end has no gteq/lteq spelling - the suite proves that raises instead of
      # searching the day the Range left out.
      filter :published_date, as: :date_range,
                              extensions: { default: -> { Date.new(2026, 1, 1)...Date.new(2026, 2, 1) } }
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

    ActiveAdmin.register Post, as: "NilMemberDefaultPost" do
      # `default: -> { [current_admin_user.team_id] }` for an admin with no team: an Array whose
      # only member is blank survives a plain blank-reject but cannot round-trip through a URL.
      filter :status, as: :check_boxes, collection: %w[draft published],
                      extensions: { default: -> { [nil] } }
    end

    ActiveAdmin.register Post, as: "BlankDefaultPolicedPost" do
      # A blank default beside a validate:. Blank is no value - the URL cannot even carry it -
      # so there is nothing for the validator to refuse.
      filter :title_cont, as: :string,
                          extensions: { default: "",
                                        validate: ->(value) { "Letters only." unless value.match?(/\\A[a-z]+\\z/) } }
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

    ActiveAdmin.register Post, as: "RequiredSiblingPost" do
      default_filters_notice "Showing kept titles by default"

      # A :string filter carries the predicate dropdown: picking "equals" submits title_eq
      # where the derived key is title_cont. Both are answers about the same column.
      filter :title, extensions: { default: "keep", required: true }
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

    ActiveAdmin.register Post, as: "WindowPost" do
      default_filters_notice "Showing the default window"

      # The capped window: never unbounded (required:), never wider than the cap, never before
      # the retention floor - the didww-rs/pbx/nessie range guards, as options.
      filter :published_date, as: :date_range,
                              extensions: { required: true,
                                        max_range: 90.days,
                                        min: -> { Date.new(2020, 6, 1) },
                                        default: -> { Date.new(2026, 5, 1)..Date.new(2026, 6, 30) } }
    end

    ActiveAdmin.register Post, as: "FloorPost" do
      # min: standing alone: a window with no lower bound scans everything before the
      # retention floor - the exact query the floor exists to refuse.
      filter :published_date, as: :date_range,
                              extensions: { min: -> { Date.new(2020, 6, 1) },
                                            default: -> { Date.new(2026, 5, 1)..Date.new(2026, 6, 30) } }
    end

    ActiveAdmin.register Post, as: "ShortWindowPost" do
      # A cap shorter than a day - reported in whole days it read "0 days".
      filter :published_date, as: :date_range, extensions: { max_range: 6.hours }
    end

    ActiveAdmin.register Post, as: "StringKeyedExtensionsPost" do
      # A string-keyed container: accepted by the unknown-key check and then silently inert.
      filter :title_cont, as: :string, extensions: { "default" => "keep" }
    end

    ActiveAdmin.register Post, as: "NilFloorPost" do
      # A per-admin retention floor that opts out for this admin - nil imposes nothing, the way
      # a nil default: does.
      filter :published_date, as: :date_range, extensions: { min: -> { nil } }
    end

    ActiveAdmin.register Post, as: "ValidatedWindowPost" do
      # Value AND window policies with a default: a scalar reset must not leave half the
      # admin's window to be completed from the default pair unchecked.
      filter :published_date, as: :date_range,
                              extensions: { max_range: 90.days,
                                            validate: ->(value) { value.include?("X") && "No X dates." },
                                            default: -> { Date.new(2026, 5, 1)..Date.new(2026, 6, 30) } }
    end

    ActiveAdmin.register Post, as: "BananaSanitizedWindowPost" do
      # Its sanitizer widens a bound past the cap AFTER the declared range looks innocent -
      # the window must be judged on what is actually stored.
      filter :published_date, as: :date_range,
                              extensions: { max_range: 90.days,
                                            sanitize: ->(value) { value == "2026-02-01" ? "2026-12-31" : value },
                                            default: -> { Date.new(2026, 1, 1)..Date.new(2026, 2, 1) } }
    end

    ActiveAdmin.register Post, as: "BananaFlatOptionPost" do
      # A gem option left outside extensions: raises - flat, it would mean Formtastic things.
      filter :title_cont, as: :string, default: "keep"
    end

    ActiveAdmin.register Post, as: "HostOptionPost" do
      # required: and min: are Formtastic input options in their own right. The gem answers to
      # them only inside extensions:, so flat they belong to the form - not to a window policy.
      filter :position, as: :number, required: true, min: 0
    end

    ActiveAdmin.register Post, as: "BananaPolicyKeyPost" do
      # A typo inside extensions: raises instead of silently guarding nothing.
      filter :title_cont, as: :string, extensions: { defult: "keep" }
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

    ActiveAdmin.register Post, as: "BananaBeginlessWindowPost" do
      # Its beginless default is unbounded below the cap - the suite proves that raises
      # instead of silently running the over-cap scan on every bare visit.
      filter :published_date, as: :date_range,
                              extensions: { max_range: 90.days,
                                        default: -> { (..(Date.current + 1)) } }
    end

    ActiveAdmin.register Post, as: "BananaWindowPost" do
      # Its default violates its own cap - the suite proves that raises instead of looping.
      filter :published_date, as: :date_range,
                              extensions: { max_range: 90.days,
                                        default: -> { Date.new(2026, 1, 1).. } }
    end

    ActiveAdmin.register Post, as: "RejectPost" do
      # :reject - the didww-api-3 add_integer_filter_check shape: flash and bounce back.
      filter :title_cont, as: :string,
                          extensions: { on_invalid: :reject,
                                    validate: ->(value) { value.match?(/\\d/) && "Title must not contain digits." } }
      filter :position, as: :numeric,
                        extensions: { on_invalid: :reject,
                                  validate: ->(value) { :invalid unless value.match?(/\\A\\d+\\z/) } }
    end

    ActiveAdmin.register Post, as: "EmptyPost" do
      # :empty - the invoice name_eq shape: show nothing, but SAY WHY, and keep the admin's
      # input in the form so they can fix it.
      filter :title_cont, as: :string,
                          extensions: { on_invalid: :empty,
                                    validate: ->(value) { value.match?(/\\d/) && "Title filter must not contain digits." } }
    end

    ActiveAdmin.register Post, as: "PairedPost" do
      # The year/month shape: either both halves of the pair or neither - half a key is a
      # question the index cannot answer honestly. Declared on both members on purpose: the
      # mirrored declarations must dedupe to one group, one warning.
      filter :status, as: :select, collection: %w[draft published],
                      extensions: { default: "published", with: :starred_eq }
      filter :starred, extensions: { default: true, with: :status_eq }
    end

    ActiveAdmin.register Post, as: "RequiredPairPost" do
      # A required member of a with: group: its refill must pull the partner's default along,
      # or the merge hands Ransack the half-group the enforcement just promised away.
      filter :title_cont, as: :string
      filter :status, as: :select, collection: %w[draft published],
                      extensions: { default: "published", required: true, with: :starred_eq }
      filter :starred, extensions: { default: false }
    end

    ActiveAdmin.register Post, as: "ChainedPairPost" do
      # Two with: groups sharing status_eq - resetting one half must not orphan the other
      # group's membership: the overlap makes them one question.
      filter :title_cont, as: :string, extensions: { with: :status_eq }
      filter :status, as: :select, collection: %w[draft published],
                      extensions: { with: :starred_eq }
      filter :starred
    end

    ActiveAdmin.register Post, as: "NilPairedPost" do
      default_filters_notice "Showing published starred posts by default"

      # A member of a with: group whose default opts out for this admin. Declared, so the group
      # is complete; nil, so it imposes nothing - and neither does the partner.
      filter :status, as: :select, collection: %w[draft published],
                      extensions: { default: "published", with: :starred_eq }
      filter :starred, extensions: { default: -> { nil } }
    end

    ActiveAdmin.register Post, as: "BananaHalfPairedPost" do
      # Half the with: group declares a default - the fallback would execute the very
      # half-group the enforcement refuses. The suite proves that raises.
      filter :status, as: :select, collection: %w[draft published],
                      extensions: { default: "published", with: :starred_eq }
      filter :starred
    end

    ActiveAdmin.register Post, as: "SplitPairPost" do
      # Two single-ended filters on ONE attribute, linked by with:. Grouped by stripped
      # attribute they look like one two-ended input, so half an answer passed as a whole group.
      filter :position_gteq, as: :string, extensions: { with: :position_lteq }
      filter :position_lteq, as: :string
    end

    ActiveAdmin.register Post, as: "BananaSplitPairPost" do
      # Only one half of a split pair declares a default - the fallback would run the very
      # half-group the enforcement refuses. The suite proves that raises.
      filter :position_gteq, as: :string, extensions: { default: "10", with: :position_lteq }
      filter :position_lteq, as: :string
    end

    ActiveAdmin.register Post, as: "PairedDatePost" do
      # Declared on ONE member - the partner's side must trip the same group - and on a
      # two-ended filter, whose predicates the warning must still humanize away.
      filter :published_date, as: :date_range, extensions: { with: :position_eq }
      filter :position
    end

    ActiveAdmin.register Post, as: "OpenPairedPost" do
      # A two-ended member of a with: group whose default fills only the end it has - the group
      # is answered by that bound, not left half-declared.
      filter :published_date, as: :date_range,
                              extensions: { default: -> { Date.new(2026, 5, 1).. }, with: :position_eq }
      filter :position, extensions: { default: { eq: 20 } }
    end

    ActiveAdmin.register Post, as: "PickyPost" do
      # The active-calls shape: this index answers no question at all until it is asked one.
      require_any_filter notice: "You must specify at least one filter"

      # A scope tab is a question too - and the one Active Admin puts a count on.
      scope(:published) { |posts| posts.where(status: "published") }

      filter :title_cont, as: :string,
                          extensions: { validate: ->(value) { value.match?(/\\d/) && "Title must not contain digits." } }
      filter :status, as: :select, collection: %w[draft published]
    end

    ActiveAdmin.register Post, as: "EmptyDigitsPost" do
      # :empty behind a sanitizer that can empty the value: the verdict must survive the
      # canonicalizing redirect, or the next request renders the whole table.
      filter :position_eq, as: :string,
                          extensions: { sanitize: :digits, validate: :integer, on_invalid: :empty }
    end

    ActiveAdmin.register Post, as: "EmptyDigitsArrayPost" do
      # A genuine multi-value filter: unlike the scalar filter above, its check boxes submit
      # q[status_in][] and can therefore render the preserved array back to the admin.
      filter :status, as: :check_boxes,
                      collection: [["Not a number", "abc"], "draft", "published"],
                      extensions: { sanitize: :digits, validate: :integer, on_invalid: :empty }
    end

    ActiveAdmin.register Post, as: "RejectWindowPost" do
      # Value AND window policies on one :reject filter: the second violation must not answer
      # an already-answered request.
      filter :published_date, as: :date_range,
                              extensions: { max_range: 30.days, on_invalid: :reject,
                                            validate: ->(value) { value.include?("X") && "No X dates." } }
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

    ActiveAdmin.register Post, as: "ParameterizedSymbolPost" do
      # A validate: answering one of the gem's own parameterized symbols - which the docs
      # invite - with nothing to interpolate %{limit} from.
      filter :title_cont, as: :string,
                          extensions: { validate: ->(value) { value.match?(/\\d/) && :range_too_wide } }
    end

    ActiveAdmin.register Post, as: "InterpolatedMessagePost" do
      # message: in the app's own words, naming the gem's own interpolation.
      filter :published_date, as: :date_range,
                              extensions: { max_range: 90.days,
                                            message: "Pick at most %{limit}." }
    end

    ActiveAdmin.register Post, as: "BananaNoticeKeyPost" do
      # require_any_filter named with a Symbol no locale defines.
      require_any_filter notice: :no_such_notice_key

      filter :title_cont, as: :string
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
