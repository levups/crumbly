# Crumbly

Breadcrumbs for Rails: namespaced, derived from your routes, checked in tests.

<https://levups.github.io/crumbly/>: guide, migration from gretel, breadcrumbs_on_rails and loaf, benchmarks.

[gretel](https://github.com/kzkn/gretel) works, but on a real back office (one file of about 1,000 lines,
265 crumbs, 380 call sites), its shape is what hurts:

- one global file and one flat namespace, where a crumb defined twice silently replaces the first, and an
  admin area cannot keep its breadcrumbs apart from a storefront's;
- mistakes that only show when someone opens the page;
- blocks run through `instance_exec` and helpers reached through `method_missing`;
- every trail written by hand, even when the routes already describe it.

Crumbly keeps gretel's good idea (a crumb names its parent) and changes the rest:

- **One class per namespace.** `Admin::Breadcrumbs` and `Storefront::Breadcrumbs` each hold their own crumbs,
  under the same names if they like. Zeitwerk loads them, so they load before a prefork server forks.
- **One crumb per Ruby method.** The parent is a plain method call, and the URL helpers come from your routes.
  There is no DSL to learn and no `method_missing`, and a backtrace points at the method.
- **Derived by default.** A view that names no crumb gets the trail of its action, built from the routes and
  the record its controller loaded.
- **Mistakes raise early.** A crumb defined twice raises when the class loads, and an unknown crumb raises in
  development and test. In production it is reported and the page renders without a trail.
- **Data, not HTML.** `breadcrumb_trail` returns levels (label, URL, extra links, `current?`), and your own
  component renders them.

## Installation

```ruby
gem "crumbly"
```

The railtie adds `breadcrumb`, `breadcrumb_trail` and `breadcrumb_json_ld` to your views, and `breadcrumbs_with` to your controllers.

## Usage

```ruby
# app/breadcrumbs/admin/breadcrumbs.rb
module Admin
  class Breadcrumbs < Crumbly::Trail
    def root
      crumb "Home", admin_root_path
    end

    def orders
      crumb "Orders", admin_orders_path
    end

    def order(order)
      crumb order.to_s, admin_order_path(order), parent: orders
    end
  end
end
```

```erb
<%# app/views/admin/orders/show.html.erb: optional, this is what the trail derives on its own %>
<% breadcrumb @order %>

<%# app/views/layouts/admin.html.erb %>
<nav aria-label="Breadcrumb">
  <ol>
    <% breadcrumb_trail.each do |level| %>
      <li><%= link_to_unless level.current?, level.label, level.url %></li>
    <% end %>
  </ol>
</nav>
```

- `breadcrumb :name, *arguments` calls the crumb named `name`, and `breadcrumb @record` calls the crumb named
  after the record's model (`order` for an `Order`). For a single-table inheritance subclass with no crumb of
  its own, it falls back on its parent class's.
- `root`, when you define it, starts every trail.
- `crumb label, url = nil, parent: nil, links: []`. `url` takes a string, a record or a polymorphic array
  (`[:admin, owner, :returns]`), or nothing for a level without a link. `links:` holds extra
  `link(label, url)`s for a level that points to more than one page.
- `crumb_for(record)` is the crumb of a record found by its model, which is how you write a polymorphic parent.
- Private methods are helpers, not crumbs. View helpers are reached through `helpers` (`helpers.t(".orders")`).
- Every name that works in a view is a crumb, so `Crumbly::Trail` keeps its own methods private. The ones
  your crumbs must not be named after are `crumb`, `link`, `crumb_for` and `helpers`.

### Namespaces

`Admin::OrdersController` reads `Admin::Breadcrumbs`, falling back on enclosing modules and then on a
top-level `Breadcrumbs`. A controller elsewhere picks one explicitly:

```ruby
class CheckoutController < ApplicationController
  breadcrumbs_with Storefront::Breadcrumbs
end
```

### Derived trails

When a view does not call `breadcrumb`, the trail follows the action:

| Action | Trail |
|---|---|
| `index` | the collection: your `posts` crumb, or else the model's plural name linked to the `index` route |
| `show` | the record: your `post` crumb, or else `to_s` linked to the `show` route, under the collection |
| `new`, `create` | "New" (`crumbly.new`) under the collection |
| `edit`, `update` | "Edit" (`crumbly.edit`) under the record |

The record is the one the controller already loaded (`@post` in `PostsController`): it is never looked up
again. To change how a trail is derived, override the private methods `collection_crumb`, `record_crumb`,
`new_record_crumb` or `edit_record_crumb`.

Under a nested route, each `:<name>_id` path parameter is a parent level, outermost first.
`/admin/posts/5/comments` gives Comments under Post 5 under Posts, the post being `@post`, as the controller
loaded it: your `post` crumb, or else its `to_s` linked to its `show` route, under the posts collection. A
parent the controller did not load is never queried: the trail skips the nesting's crumb, keeps that parent's
collection (Posts) and goes straight to the current level.

### Order of precedence

For any page, the first of these that applies builds the trail:

1. The view's `breadcrumb`.
2. The namespace's crumb named after the controller: `posts` in `Admin::PostsController#index`, and under a
   nested route the whole nesting, called with the parents' records (`order_messages(order)` for
   `/admin/orders/42/messages`). On `show` and `edit`, the crumb named after the record's model (`post`).
3. The derived trail, whose parent levels follow the same order: your crumb for the parent's model, or else
   the derived level.

## Five real-world cases, side by side

### A nested resource

```ruby
# gretel, config/breadcrumbs.rb
crumb :order_messages do |order|
  link "Messages", admin_order_messages_path(order)
  parent :order, order
end
```

```ruby
# Crumbly, app/breadcrumbs/admin/breadcrumbs.rb: optional, the nested route derives the same trail
def order_messages(order)
  crumb "Messages", admin_order_messages_path(order), parent: order(order)
end
```

### A polymorphic parent

```ruby
# gretel
crumb :returns do |owner|
  if owner
    link "Returns", [:admin, owner, :returns]
    parent owner
  else
    link "Returns", admin_returns_path
  end
end
```

```ruby
# Crumbly
def returns(owner = nil)
  return crumb("Returns", admin_returns_path) unless owner

  crumb "Returns", [:admin, owner, :returns], parent: crumb_for(owner)
end
```

### A label computed from the record

```ruby
# gretel
crumb :order do |order|
  link "Order #{order.number}", admin_order_path(order)
  if order.customer
    parent :customer_orders, order.customer
  else
    parent :orders
  end
end
```

```ruby
# Crumbly
def order(order)
  crumb "Order #{order.number}", admin_order_path(order),
    parent: order.customer ? customer_orders(order.customer) : orders
end
```

### A recursive tree

The ancestors are loaded once, in one query, and handed down the recursion:

```ruby
# gretel
crumb :category do |category, ancestors = category.ancestors.to_a|
  link category.name, admin_category_path(category)
  *grandparents, parent_category = ancestors
  parent_category ? parent(:category, parent_category, grandparents) : parent(:categories)
end
```

```ruby
# Crumbly
def category(category, ancestors = category.ancestors.to_a)
  *grandparents, parent_category = ancestors
  crumb category.name, admin_category_path(category),
    parent: parent_category ? category(parent_category, grandparents) : categories
end
```

### A form

```ruby
# gretel: one generic crumb, called from each new and edit view
crumb :generic_form do |model|
  if model.new_record?
    link "New", nil
    parent model.class.model_name.plural.to_sym
  else
    link "Edit", nil
    parent model
  end
end
```

```erb
<%# app/views/admin/posts/edit.html.erb %>
<% breadcrumb :generic_form, @post %>
```

```ruby
# Crumbly: nothing to write. new and edit derive "New" under the collection, "Edit" under the record.
```

## Checked in tests

A crumb defined twice already raises when its class loads. One test checks the rest, without running a crumb
or loading a record:

```ruby
# test/breadcrumbs_test.rb
require "test_helper"
require "crumbly/test_helper"

class BreadcrumbsTest < ActiveSupport::TestCase
  test "breadcrumbs" do
    assert_breadcrumbs_valid
  end
end
```

It eager-loads the app and reads the source of every crumb (and of the private helpers next to it) with Prism:

- every parent a crumb calls is a crumb, and every `_path` or `_url` it calls is a route helper;
- every `breadcrumb :name` in `app/views` and `app/controllers` names a crumb some trail defines;
- every crumb is called with as many arguments as it takes, by its views and by other crumbs: gretel ignored
  extra arguments and passed `nil` for missing ones, a method raises `ArgumentError` (a view call spread over
  several lines, or with a splat, is not counted);
- every crumb is reachable: called by another crumb, by a view or controller (`breadcrumb :name`,
  `breadcrumb @record`), by a derived trail (the collection and record of a routed controller), or named after
  a model. The others are dead, and fail the test.

`Crumbly.verify!` does the same outside Minitest: it raises `Crumbly::InvalidTrail` with every problem
in one message, and returns the dead crumbs (`["Admin::Breadcrumbs#drafts"]`). Both take `trail_classes:`,
`routes:` and `sources:` (the directories scanned for `breadcrumb` calls).

## Storefronts

The trail is data, so absolute URLs are just `_url` helpers in that namespace's crumbs:

```ruby
module Storefront
  class Breadcrumbs < Crumbly::Trail
    def category(category)
      crumb category.name, storefront_category_url(category),
        parent: category.parent ? category(category.parent) : shop
    end
  end
end
```

`breadcrumb_json_ld` renders the same trail as a schema.org `BreadcrumbList`, the structured data Google reads
for its breadcrumb rich result:

```erb
<%# app/views/layouts/storefront.html.erb, in <head> %>
<%= breadcrumb_json_ld %>
```

- Positions start at 1, and the current level may have no URL. A level above it without a URL is not a page,
  so it is left out.
- A name is plain text: an `html_safe` label (an icon, a `<b>`) has its markup stripped and its entities decoded.
- The JSON is escaped for a `<script>` tag, so a label cannot close it.
- Google only takes absolute URLs: a relative one raises `Crumbly::RelativeUrl` in development and test.
  In production it is reported and the page renders without a `BreadcrumbList`. Set
  `Crumbly.raise_on_relative_url` to choose.
- `Crumbly::JsonLd.call(levels)` returns the `BreadcrumbList` as a hash, for a page that builds its own
  structured data.

## Migrating from gretel

An app switches in one go: there is no compatibility layer, and the two gems do not run side by side in
production. gretel stays in the Gemfile of the migration branch only, for the comparison test below.

### 1. Convert the breadcrumbs file

```sh
bundle exec crumbly-convert config/breadcrumbs.rb --namespace Admin \
  --output app/breadcrumbs/admin/breadcrumbs.rb --views app/views/admin
```

It writes `Admin::Breadcrumbs` and prints, with their line, what it left out or converted with a loss. Several
files (`config/breadcrumbs/*.rb`) make one class, the later definition of a crumb winning as in gretel.

| gretel | Crumbly |
|---|---|
| `crumb :key do \|order\| ... end` | `def key(order) ... end`, a parameter tested for nil getting `= nil` |
| `link label, url` | `crumb label, url`; `link label` or `link label, nil` give a level without a URL |
| a second `link` | `links: [link(label, url)]` on the same level |
| `parent :other, order` | `parent: other(order)` |
| `parent record` | `parent: crumb_for(record)` |
| `parent :a` and `parent :b` in an `if`/`else` | `parent: condition ? a : b` |
| `parent :a`, then `parent :b if condition` | `parent: condition ? b : a` |
| `link` and `parent` inside an `if`, `elsif`, `unless` or `case`, modifiers included | one `crumb` call per branch, the statements after the conditional copied into each |
| `t(".x")`, `current_user`: view helpers | `helpers.t(".x")`, `helpers.current_user`; route helpers stay bare |
| `%i[a b].each { \|name\| crumb name do ... end }`, `{a: [:post, Comment]}.each { \|name, (parent, model)\| ... }` | one method per element |
| a local assigned before a crumb reads it: `path = :"admin_#{name}_path"` | copied into each crumb reading it, a literal written in place |
| `label = ->(record) { ... }` at the top of the file, reading no other local | a private method, `label.call(post)` becoming `label(post)` |

It lists, without converting them: a loop over anything but a literal array or hash (of symbols, strings,
numbers and constants), `link` or `parent` inside anything but a conditional (a loop, a block), `link` options
(`title:`, `class:`), crumbs whose name is a Ruby keyword or an existing method (`display`, `test`), and any
statement that is not a crumb, a loop or a local. Comments are kept above the method they precede.

The codemod is built on Prism 1.2 or later: Ruby 3.4 ships it, and on Ruby 3.3 add `gem "prism"` to the
development group.

### 2. Compare the trails

While gretel is still bundled, the tests draw each trail with both gems and list the differences in labels and
URLs. gretel shows a crumb's extra links as levels of their own: the comparison does the same with `links`. Keep
gretel in the test group with `require: false`: `crumbly/oracle` loads it, without the view helpers whose
`breadcrumb` would replace Crumbly's.

```ruby
# Gemfile, on the migration branch
gem "gretel", require: false, group: :test
```

The views already call `breadcrumb` the way Crumbly expects, so the app's own controller, integration and system
tests can do the comparing. With `Crumbly::Oracle.watch` in the test helper, every page they render is drawn by
gretel too, from the same `breadcrumb` call:

```ruby
# test/test_helper.rb, once the app is loaded
require "crumbly/oracle"

Crumbly::Oracle.watch
Minitest.after_run do
  puts Crumbly::Oracle.differences.to_a, Crumbly::Oracle.redundant_calls.to_a
end
```

`differences` holds each page whose trail changed, gretel's and Crumbly's side by side, including the pages
without a `breadcrumb` call, which gretel left without a trail and which now derive one. `redundant_calls`
holds the calls whose trail the action derives anyway. `watch { ... }` watches a block only. Parallel test
workers each fill their own lists, which `after_run` in the parent process never sees: run the watched suite
with `PARALLEL_WORKERS=1`. A call gretel cannot draw shows as a difference, with gretel's error.

For the crumbs no test renders, `compare` takes the calls to check:

```ruby
class BreadcrumbsMigrationTest < ActionView::TestCase
  test "Crumbly draws the trails gretel drew" do
    differences = Crumbly::Oracle.compare(view, Admin::Breadcrumbs, [
      [:orders], [:order, orders(:alice)], [orders(:alice)], [:returns], [:returns, customers(:alice)]
    ])

    assert_empty differences, differences.join("\n")
  end
end
```

### 3. Review the call sites

`--views` lists the `breadcrumb` calls that a derived trail may now cover: `:generic_form` (or `:new`,
`:edit`) in new and edit views, `breadcrumb @order` in a show view, `breadcrumb :orders` in an index view.
Nothing is deleted: a call goes once its view shows the same trail without it, which is what
`Crumbly::Oracle.redundant_calls` lists for the pages the tests render.

### 4. Remove gretel

Drop gretel and `config/breadcrumbs.rb`, and render `breadcrumb_trail` in the layout where `breadcrumbs` was.

## Requirements

Ruby 3.3 or later, and Rails 8.0 or later (Action Pack and Active Support).

## Performance

`bench/render.rb` renders the same five-level trail (Home > Customers > Alice > Orders > Order 2026-0042) with
gretel and with Crumbly, and checks that both produce the same output. The `<ol>` is gretel's
`breadcrumbs(style: :ol)` against a ten-line helper over `breadcrumb_trail`. The JSON-LD is gretel's
`structured_data(url_base:)` (paths behind a prefix) against `breadcrumb_json_ld` (`_url` helpers), both
encoded and escaped the same way.

Ruby 4.0.9, Rails 8.1.4, gretel 5.1.0, Apple M5 (arm64 macOS), median of three runs of benchmark-ips:

| Render | Allocations | Time, YJIT off | Time, YJIT on |
|---|---|---|---|
| gretel `<ol>` | 345 | 57.6 µs | 35.1 µs |
| Crumbly `<ol>` | 274 | 45.4 µs | 29.8 µs |
| gretel JSON-LD | 268 | 41.3 µs | 25.4 µs |
| Crumbly JSON-LD | 287 | 43.3 µs | 29.5 µs |

Most of the JSON-LD gap comes from Rails' `_url` helpers, which are slower than `_path` ones: building the
`BreadcrumbList` from the levels accounts for 1.7 µs of it.

```sh
bundle exec ruby bench/render.rb
bundle exec ruby --yjit bench/render.rb
```

## Development

```sh
bundle install
bundle exec rake test                                            # latest Rails
BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle exec rake test  # Rails 8.0
bundle exec rubocop
```

### Releasing

Pull requests leave `CHANGELOG.md` alone: a release starts by writing its notes under `## [Unreleased]`, from the
pull requests merged since the last tag, without committing them. Then, from an up-to-date `main` whose CI is
green:

```sh
bin/release minor --dry-run   # the notes and the changes, nothing written
bin/release minor             # or patch, major, or an exact version such as 1.2.0
```

`main` takes no direct push, so `bin/release` dates the Unreleased section and bumps the version on a branch
`release/vX.Y.Z`, opens its pull request, which merges itself once CI is green, and waits for it. It then pushes a
signed tag `vX.Y.Z` on the merge commit (`bin/release --tag X.Y.Z` does it if you stopped waiting). The tag starts
the Release workflow, which publishes the gem to RubyGems through trusted publishing and creates the GitHub release
with the version's notes and the `.gem`.

## License

MIT, by Level UP Solutions. Crumbly keeps the idea of [gretel](https://github.com/kzkn/gretel), by Lasse Bunk and
Kazuki Nishikawa: a crumb names its parent.
