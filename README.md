# active_admin_filter_extensions

Declarative extensions for Active Admin index filters: defaults, mandatory windows, value
policies and honest URLs - one `extensions:` option on the filter instead of a hand-rolled
`before_action` mutating `params[:q]`.

```ruby
filter :created_at, as: :date_time_range,
       extensions: { required: { unless: %i[id_eq uuid_eq] },  # the window every request gets...
                     default:   -> { 1.day.ago.beginning_of_day.. },  # ...and what it defaults to
                     max_range: 90.days }                      # wider is refused, loudly
```

**What ships:**

* [`default:`](#usage) - the filter's default value: scalar, Range, Hash of predicates, or a
  per-request Proc; applied to a bare visit, absent from one the admin filtered themselves.
* [`required:`](#required-filters-the-mandatory-window) - the mandatory window: the default
  applies whenever the filter's keys are absent, whatever else the request carries;
  `{ if:/unless: key(s) }` names the searches that switch it on or off.
* [`with:`](#filters-that-only-make-sense-together) - all-or-none groups (year with month):
  half an answer resets to the defaults with a warning.
* [`sanitize:` / `validate:`](#value-policies-sanitize-and-validate) - strip what typing drags
  in, refuse what the search cannot mean; built-ins `:digits`, `:integer`, `:ip`.
* [`on_invalid:`](#on_invalid-what-a-violated-policy-does) - what a violation does: `:reset`
  (drop + refill the default), `:reject` (bounce back), `:empty` (render nothing, keep the input).
* [`max_range:` / `min:`](#window-policies-max_range-and-min) - range caps and retention
  floors on two-ended filters.
* [`message:`](#value-policies-sanitize-and-validate) and plain-i18n defaults for every
  violation text.
* [`default_filters_notice`](#telling-the-admin-why) - the flash that tells the admin why the
  page shows a slice; [`require_any_filter`](#resource-level-guard) - an index that waits to
  be asked.
* [The redirect](#the-redirect) - a bare HTML visit answers with one 302 to itself with the
  effective filters spelled out, so a copied URL shows the same page to whoever opens it.

Some index pages are not "a list you may want to narrow down", they are "a list that is only
meaningful, or only affordable, inside a window": a log table partitioned by date, a page backed
by an external service that will not answer an unbounded query, a queue an agent should land on.
Active Admin has no way to say so, so every app of this size grows a `before_action` that mutates
`params[:q]`. This is that, as options on the filter itself.

```ruby
ActiveAdmin.register Order do
  filter :state_eq, as: :select, collection: %w[pending paid], extensions: { default: "pending" }
end
```

## Install

```ruby
gem "active_admin_filter_extensions", github: "activeadmin-plugins/active_admin_filter_extensions"
```

Not on RubyGems yet; pin the tag.

## The extensions: container

Everything this gem adds lives under one filter option, so its names can never collide with
Formtastic's. A gem key left flat raises rather than quietly meaning something else:

```ruby
filter :title_cont, as: :string, extensions: { default: "acme" }   # right
filter :title_cont, as: :string, default: "acme"                  # raises
```

With one carve-out: `required:` and `min:` are Formtastic input options in their own right, so
flat they belong to the form and pass through untouched. This gem answers to them only inside
`extensions:`.

```ruby
filter :position, as: :number, min: 0                          # Formtastic's - renders min="0"
filter :created_at, as: :date_range, extensions: { min: -> { 2.months.ago } }  # the gem's floor
```

## Usage

A default is a **value**. Which Ransack key it lands under is the input's business, and the
input is asked - so a `:select` gets `_eq`, a `:check_boxes` gets `_in` under the association's
primary key, and a `:string` gets whichever predicate heads its dropdown, including when the
resource or the namespace has reordered that list:

```ruby
filter :status,     as: :select,      extensions: { default: "active" }
filter :author,     as: :check_boxes, extensions: { default: [1, 2] }
filter :created_at, as: :date_range,  extensions: { default: -> { 1.week.ago..Time.current } }
filter :created_at, as: :date_range,  extensions: { default: -> { 1.week.ago.. } }  # lower bound only
filter :title,                        extensions: { default: "acme" }
```

**A Range** fills a two-ended input, one bound per end; leave an end off and that end is left to
the admin. Handing a single value to a two-ended input raises, rather than picking an end for you.
So does an exclusive range (`a...b`): the input submits `gteq` and `lteq`, so the excluded end has
no spelling there and would be searched after all.

Anything relative to now belongs in a Proc, as above. `filter` runs when the resource file is
loaded, so `default: 1.week.ago..` would pin the window to the moment the process booted and let
it drift for as long as that process lives - quietly, and worst on the long-running ones. A Proc
is re-read on every request.

**A Proc** is evaluated against the controller on every request, and a `nil` result applies no
filter, which is how a default is made conditional or read off the signed-in admin:

```ruby
filter :author_id_eq, extensions: { default: -> { current_admin_user.id unless current_admin_user.admin? } }
filter :queue_eq,     extensions: { default: -> { current_admin_user.default_queue } }
```

Asking the input means you get whatever that input actually submits, which is not always the
predicate the docs of some other app would lead you to expect. A `:string` filter submits the
head of its dropdown, and an app that re-registers Ransack's aliases - `contains`, `equals`,
`starts_with` - reorders that list, so `default: "acme"` may search for equality rather than a
substring. That is correct, since it is what an untouched form submits there, but check it
rather than assume.

Deriving needs a resource Ransack can search. A resource backed by something else - an
ActiveResource model standing in for an HTTP API, say - has no `ransack`, and the derivation
raises rather than guessing:

    filter :created_at declares a `default:` but could not work out which search key it submits
    (NoMethodError: undefined method 'ransack' ...) - name the predicate with a Hash instead

**A Hash** names the predicates outright, for that case and for when the input's own predicate
is not the one you want:

```ruby
filter :title, extensions: { default: { eq: "acme" } }     # rather than the _cont it would submit
filter :created_at, as: :date_range, extensions: { default: { gteq: -> { 1.week.ago } } }
```

A filter hidden by `:if` or `:unless` imposes no default either — it would filter the collection
with no control on screen to undo it.

## Getting out of a default

Defaults apply only while the request carries no filters of its own.

* The default also seeds the visible form, so the admin can see why the list is filtered and edit
  that value like any other filter.
* **Blank the field and press Filter** to see the unfiltered collection. Active Admin disables
  empty fields on submit, so a blank submission sends no `q` at all and is told apart from a first
  visit by `commit`.
* **Clear Filters** drops `commit` along with `q`, so it returns the page to its defaults rather
  than to an empty filter set.

## Widening when the defaults apply

By default they apply to a request that carries no filters of its own. A resource that always
carries something in `q` — a customer id pinned by a nested route, say — can widen that:

```ruby
controller do
  def filter_defaults_apply?
    super || params[:q].keys == %w[customer_id_eq]
  end
end
```

Whatever the request asked for wins over a default, so the pinned value survives.

## Telling the admin why

An index that quietly shows a slice of the table owes the admin a word about it:

```ruby
ActiveAdmin.register Export do
  default_filters_notice "Records for the last month are displayed by default"
  filter :created_at, as: :date_range, extensions: { default: { gteq: -> { 1.month.ago } } }
end
```

The message is flashed only when the defaults actually took effect. Pass `flash_key:` to use
something other than `:notice`.

## Required filters: the mandatory window

Some tables must never be queried without a bound - a log partitioned by date, a CDR table
where an unbounded scan is an outage. `required: true` promotes the filter's default from
"applies to a bare request" to "applies whenever THIS filter's keys are absent", whatever
else the request carries - and a blank filters-form submission gets the window back rather
than the whole table:

```ruby
filter :time_start, as: :date_time_range,
       extensions: { required: { unless: %i[id_eq uuid_eq] },  # a search naming one record escapes it
                 default:  -> { 1.day.ago.beginning_of_day..Date.tomorrow.end_of_day } }
```

`required: true` is unconditional. A Hash narrows it: `{ unless: keys }` excuses the window
beside those keys, `{ if: keys }` imposes it only beside those keys; both take a Symbol or an
Array and combine.

The required window is group-wide: a request that touched ANY of the filter's own keys has
answered it - an upper bound alone is honored as given, never completed from the default
into a pair the admin did not mean. What a half-open range may not mean is `max_range:`'s
business. `required:` without a `default:` raises on the first index request: mandatory with nothing
to fall back on is a configuration error, not a quiet empty page. The defaults notice
speaks whenever a default actually reached the search - including onto a partly-filtered
request.

## What the policies do and do not guard

A value policy watches every request key that names its filter's attribute - the derived
head key and the sibling predicates a dropdown submits (`position_gt` beside a policed
`position_eq`). The deliberate boundaries:

* **Window, required and with: groups watch their derived and named keys** - not arbitrary
  predicates of other attributes. Policies are guard rails for the UI the filter renders -
  for hostile-proof filtering, whitelist at the model
  (`ransackable_attributes`/`ransackable_scopes`), which is also where Ransack itself draws
  the trust line.
* **A policed key refuses non-string shapes.** `?q[title_cont][value]=x` executes
  byte-identically to the scalar, so a Hash- or Array-wrapped value on a policed key is
  treated as a violation, not ignored.
* **A `required:` filter whose Proc default resolves to nil imposes nothing for that
  request.** That is how a per-admin default opts out ("no COMMERCIAL narrowing for this
  admin"); for a window that must never be absent, return a window from every branch of the
  Proc.
* **`sanitize:` must be idempotent** - sanitizing its own output must change nothing. In the
  redirect the sanitized value comes back in the URL for another pass; a sanitizer
  that keeps rewriting is an infinite redirect, and the gem raises on the first request
  instead of looping.

## Filters that only make sense together

```ruby
filter :month, as: :select, collection: 1..12,
       extensions: { default: -> { Date.current.month }, with: :year_eq }
```

A filter declared `with:` its partner key(s) - a Symbol or an Array - forms one group out of
its own search keys and the partners: either every key of the group is answered or none. A
half-answered group is reset to the declared defaults with a warning, whichever side the half
came from. Declare it on either member; mirrored declarations dedupe to the one group they
both name.

## Resource-level guard

```ruby
require_any_filter notice: "You must specify at least one filter"
```

`require_any_filter` makes an index answer no question until it is asked one: a bare visit -
a blank form submission included - renders an empty collection with the notice, never the
whole table. Resource-level on purpose: "any filter at all" belongs to no single filter. A
scope tab counts as a question: Active Admin puts a count on it, and answering it with an empty
page would contradict the tab.

## on_invalid: what a violated policy does

Three named consequences, because the inventoried apps genuinely used them:

```ruby
filter :time_start, ..., extensions: { max_range: 90.days }         # :reset is the default
filter :customer_id, extensions: { validate: ->(v) { :invalid unless v.match?(/\A\d+\z/) }, on_invalid: :reject }
filter :name_eq, extensions: { validate: ->(v) { ... }, on_invalid: :empty }
```

* `:reset` - drop the offending key(s), `flash[:error]`, the declared `default:` refills.
* `:reject` - `flash[:error]` and bounce back the way the request came (bare index when
  there is no referer). Off the HTML path - a CSV or JSON index - it degrades to `:reset`:
  there is nowhere to bounce to and no flash to read.
* `:empty` - render an empty collection with the message, keeping the admin's input in the
  form: "nothing found because the value is malformed" stops masquerading as an honestly
  empty result.

The URL always ends up telling the truth: the redirect compares the
search that will actually run against the query string as the browser sent it, so a value a
policy rewrote (sanitize) or dropped redirects once to the corrected address.

## Window policies: max_range and min

The range caps and retention floors, declared where the window is:

```ruby
filter :time_start, as: :date_time_range,
       extensions: { required:  true,
                 default:   -> { 1.day.ago.beginning_of_day..Date.tomorrow.end_of_day },
                 max_range: 90.days,
                 min:       -> { 2.months.ago } }
```

A violation - unparseable bound, inverted range, wider than `max_range:`, earlier than
`min:` - resets the PAIR: both bounds dropped, one `flash[:error]`, the declared default
refills. An open upper bound is measured against now; a FUTURE lower bound with no upper
bound selects a not-yet-written window and passes. A default that would itself violate the
policy raises on first use - resetting into a refused window is a loop, not a fallback.
Messages are i18n keys under `active_admin_filter_extensions.*` (`range_invalid`,
`range_too_wide` with `%{limit}`, `before_floor` with `%{floor}`), shipped with English
defaults.

## Value policies: sanitize and validate

The guards every app of this size hand-rolls in index before_actions - strip what typing
drags in, refuse what the search cannot mean - as options on the filter itself:

```ruby
filter :ip_contains, as: :string,
       extensions: { sanitize: ->(value) { value.sub(%r{/+\z}, "") },
                 validate: :ip }                  # built-in; or a callable

filter :title_cont, as: :string,
       extensions: { default:  "acme",
                 validate: ->(value) { "Title must not contain digits." if value.match?(/\d/) } }

filter :id_eq, as: :string,
       extensions: { sanitize: :digits,               # built-in: strip to digits
                 validate: :integer }             # built-in: must fit a PG int4
```

`sanitize:` rewrites the value in place before anything reads it - including the redirect
decision, so the URL carries what was actually searched.
`validate:` answers nil for a good value, or a message: a String used verbatim, or a Symbol
looked up under the `active_admin_filter_extensions.*` i18n scope with `%{filter}` available.

On a violation the policy is `:reset`: the offending key is dropped from `q`, the message
lands in `flash[:error]` (and rides the redirect), and the filter's declared `default:` - if
any - refills through the ordinary merge. The defaults notice stays quiet on that render:
the error already explains why the page shows the default slice.

## The redirect

A bare visit to the index redirects once to itself with the effective filters spelled out in
the query string. A relative default is frozen to the dates it came to, a per-admin default
to the values this admin saw - so the address the admin copies shows the same page to whoever
opens it, instead of re-resolving the defaults against the recipient's clock and account. A
declared `default_filters_notice` rides the redirect. The price: +1 redirect on every bare
visit, and a bookmarked URL pins the defaults of the day it was made rather than following
the code. Non-HTML requests (CSV, JSON) are never redirected; the defaults filter them all
the same.

Four prints in small type:

* **Code that rewrites `q` in a `before_action`** (sanitizers that delete invalid ranges,
  say) runs after the redirect has already compared the request against the defaults - the
  URL then keeps saying what the sanitizer removed. Rewrite `q` before the gem sees it, or
  declare the rule as a `sanitize:`/`validate:` extension and let the redirect carry the
  corrected value.
* **The redirect runs after authentication but before Active Admin's index authorization**,
  so an authenticated admin without read rights on a resource still receives the 302 whose
  Location spells out that resource's defaults. Keep per-role secrets out of defaults.
* **Ransack's structural keys are stripped on resources that declare something of this
  gem's.** `q[m]`, `q[g]` and `q[c]` turn a required, capped window into `window OR anything`
  and nest conditions no value policy ever sees, so where a policy guards the filters they
  are a bypass rather than an answer. A resource that declares no extension keeps them - the
  hand-built `q[g]` OR link is the standard Active Admin workaround. Sorting (`q[s]`) is
  never a condition and is never touched.
* **Anything that reads `params[:q]` for the effective filters** (drill-down links, exports)
  should read `filtering_params` instead - on the rendered page they agree, but only
  `filtering_params` is also right on the non-redirected formats.

Tested against Active Admin 3.5 on Rails 8.0 and 8.1, under Ruby 3.3, 3.4 and 4.0.

## License

MIT
