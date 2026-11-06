# Crumbly

Crumbly builds breadcrumb trails for Rails apps. A breadcrumb trail is the line of links at the top of a page that
shows where it sits in the site:

```
Home › Customers › Alice › Orders › Order 2026-0042
```

You describe each level once, as a Ruby method that names its parent. Most pages need nothing more: when a view
doesn't say which trail it wants, Crumbly works it out from the controller, the action and the routes. A test
checks every trail in the app, so a broken one fails CI before anyone opens the page.

The guide, the migration notes and the benchmarks are also on the website: <https://levups.github.io/crumbly/>.

## Installation

Add the gem to your Gemfile:

```ruby
gem "crumbly"
```

It needs Ruby 3.3 or later and Rails 8.0 or later. There is nothing to configure: the gem adds `breadcrumb`,
`breadcrumb_trail` and `breadcrumb_json_ld` to your views, and `breadcrumbs_with` to your controllers.

## Getting started

### 1. Write the crumbs

Crumbs live in a class that inherits from `Crumbly::Trail`. Every public method in it is a crumb. A crumb returns
a label and a URL, and its parent if it has one:

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

The parent of `order` is the result of calling `orders`, so the trail of an order page is Home › Orders ›
Order 42. When `root` exists, every trail starts with it. Your route helpers work inside the class as they do in
a view. Rails loads the file like any other in `app/`, so `app/breadcrumbs/admin/breadcrumbs.rb` defines
`Admin::Breadcrumbs`.

### 2. Render the trail in the layout

`breadcrumb_trail` returns the levels of the current page, from the root to the page itself. Each level has a
`label`, a `url` and `current?`, which is true for the last one. The HTML is up to you:

```erb
<%# app/views/layouts/admin.html.erb %>
<nav aria-label="Breadcrumb">
  <ol>
    <% breadcrumb_trail.each do |level| %>
      <li><%= link_to_unless level.current?, level.label, level.url %></li>
    <% end %>
  </ol>
</nav>
```

### 3. Pick a crumb in a view, when you need to

A view can name the crumb it wants:

```erb
<%# app/views/admin/orders/show.html.erb %>
<% breadcrumb @order %>
```

`breadcrumb @order` calls the crumb named after the record's model, `order` for an `Order`. To call a crumb by
name, write `breadcrumb :orders`, and pass its arguments after the name (`breadcrumb :order, @order`).

In this example the line isn't needed. A `show` page with no `breadcrumb` call already gets the trail of its
record (see [Trails Crumbly works out on its own](#trails-crumbly-works-out-on-its-own)).

## Writing crumbs

A crumb calls `crumb label, url = nil, parent: nil, links: []`.

`url` can be a string, a record or a polymorphic array such as `[:admin, owner, :returns]`. Leave it out for a
level without a link. A `javascript:`, `vbscript:` or `data:` URL would run a script once your layout links it,
so Crumbly refuses it, however it is spelled (`" JavaScript:"`, `"java\tscript:"`): see
[Mistakes in development and in production](#mistakes-in-development-and-in-production).

`links:` is for a level that points to more than one page. It takes extra `link(label, url)` entries, which your
layout reads from `level.links`.

`crumb_for(record)` finds the crumb of a record from its model. Use it when the parent can be one of several
models:

```ruby
def returns(owner = nil)
  return crumb("Returns", admin_returns_path) unless owner

  crumb "Returns", [:admin, owner, :returns], parent: crumb_for(owner)
end
```

For a single-table inheritance subclass that has no crumb of its own, `crumb_for` and `breadcrumb @record` use the
crumb of its parent class.

Private methods are helpers, not crumbs, so you can put shared code in them. View helpers such as `t` or
`current_user` are reached through `helpers`: `helpers.t(".orders")`.

Any public method can be called from a view, so `Crumbly::Trail` keeps its own methods private. Don't name a crumb
`crumb`, `link`, `crumb_for` or `helpers`.

## One trail class per namespace

`Admin::OrdersController` uses `Admin::Breadcrumbs`. If there is none, Crumbly looks in the enclosing modules,
then for a top-level `Breadcrumbs`. An admin area and a storefront can each have an `orders` crumb, and they
don't clash.

A controller outside the namespace picks its class with `breadcrumbs_with`:

```ruby
class CheckoutController < ApplicationController
  breadcrumbs_with Storefront::Breadcrumbs
end
```

## Trails Crumbly works out on its own

When a view doesn't call `breadcrumb`, Crumbly builds the trail from the action:

| Action | Trail |
|---|---|
| `index` | the collection: your `posts` crumb if you wrote one, or else the model's plural name linked to the `index` route |
| `show` | the record: your `post` crumb, or else its `to_s` linked to the `show` route, under the collection |
| `new`, `create` | "New" under the collection |
| `edit`, `update` | "Edit" under the record |

The record is the one the controller has already loaded, `@post` in `PostsController`. Crumbly never runs a query
to find it. "New" and "Edit" come from the `crumbly.new` and `crumbly.edit` translations, so you can translate
them.

Nested routes work too. On `/admin/posts/5/comments`, the trail is Posts › Post 5 › Comments, and the post is
the `@post` the controller loaded. If the controller didn't load it, Crumbly skips that level and keeps Posts.

To change how these trails are built, override the private methods `collection_crumb`, `record_crumb`,
`new_record_crumb` or `edit_record_crumb` in your trail class.

### Which crumb wins

Crumbly takes the first of these that applies:

1. The crumb the view names with `breadcrumb`.
2. Your crumb named after the controller: `posts` in `Admin::PostsController#index`. Under a nested route it is
   named after the whole nesting and gets the parent records, so `/admin/orders/42/messages` calls
   `order_messages(order)`. On `show` and `edit`, it is the crumb named after the record's model (`post`).
3. The trail Crumbly works out. Its parent levels follow the same rule: your crumb for the parent's model if there
   is one, or else a level Crumbly builds.

## Testing your trails

Add one test:

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

It loads the whole app and reads the source of every crumb, without running them or touching the database. It
fails when:

- a crumb's parent is not a crumb, or a `_path` or `_url` it calls is not a route helper;
- a `breadcrumb :name` in `app/views` or `app/controllers` names a crumb that no trail class defines;
- a view or another crumb calls a crumb with the wrong number of arguments (calls spread over several lines, or
  with a splat, are skipped);
- a crumb is never used. A crumb is used when another crumb, a view or a controller calls it, when a trail
  Crumbly works out reads it, or when it is named after a model.

A crumb defined twice in the same class is caught even earlier: the class raises `Crumbly::DuplicateCrumb` when it
loads.

Outside Minitest, `Crumbly.verify!` runs the same checks. It raises `Crumbly::InvalidTrail` with every problem in
one message, and returns the unused crumbs (`["Admin::Breadcrumbs#drafts"]`). Both accept `trail_classes:`,
`routes:` and `sources:`, the directories it scans for `breadcrumb` calls.

## Mistakes in development and in production

A view that asks for a crumb that doesn't exist raises `Crumbly::UnknownCrumb` in development and test. So does
`breadcrumb @order` when `@order` is `nil`. In production the error goes to `Rails.error`, and the page renders
without a trail instead of failing.

A crumb whose URL a browser would run as a script raises `Crumbly::UnsafeUrl` in development and test. In
production the error goes to `Rails.error`, and the level keeps its label without the link.

To change either, set it in an initializer:

```ruby
# config/initializers/crumbly.rb
Crumbly.raise_on_unknown_crumb = true # on staging too
Crumbly.raise_on_unsafe_url = true
```

## Breadcrumbs for search engines

Google can show a page's trail in its results when the page describes it as schema.org structured data.
`breadcrumb_json_ld` writes that description for the current trail. Put it in the `<head>`:

```erb
<%# app/views/layouts/storefront.html.erb %>
<%= breadcrumb_json_ld %>
```

Google needs absolute URLs, so use `_url` helpers in the crumbs of that namespace:

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

A relative URL raises `Crumbly::RelativeUrl` in development and test. In production it is reported to
`Rails.error` and the page has no structured data. `Crumbly.raise_on_relative_url` changes this.

Some details of the output:

- Positions start at 1. The last level may have no URL. A level above it without a URL isn't a page, so it is
  left out.
- Names are plain text. If a label is `html_safe` (an icon, a `<b>`), its tags are removed.
- The JSON is escaped for a `<script>` tag, so a label can't close it.
- `Crumbly::JsonLd.call(levels)` returns the same data as a hash, if you build the structured data of the page
  yourself.

## Coming from gretel

Crumbly started on a back office that used [gretel](https://github.com/kzkn/gretel): one breadcrumbs file of
about 1,000 lines, with 265 crumbs and 380 calls in views. Everything lived in one global namespace, so the admin
crumbs couldn't be kept apart from the storefront's, and a crumb defined twice silently replaced the first one.
Mistakes only showed up when someone opened the page. Crumbs ran as blocks through `instance_exec`, reached the
helpers through `method_missing`, and every trail was written by hand, even when the routes already said what it
should be.

Crumbly keeps gretel's main idea, a crumb that names its parent, and writes it as plain Ruby. Here are five
crumbs from that app in both gems.

### A nested resource

```ruby
# gretel, config/breadcrumbs.rb
crumb :order_messages do |order|
  link "Messages", admin_order_messages_path(order)
  parent :order, order
end
```

```ruby
# Crumbly, app/breadcrumbs/admin/breadcrumbs.rb. Optional: the nested route gives the same trail.
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

### A tree of categories

The ancestors are loaded once, in one query, and passed down the recursion:

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
# Crumbly: nothing to write. A new page gets "New" under the collection, an edit page "Edit" under the record.
```

## Migrating from gretel

The switch happens in one go. There is no compatibility layer, and the two gems don't run side by side in
production. gretel stays in the Gemfile of the migration branch only, for the comparison in step 2.

### 1. Convert the breadcrumbs file

```sh
bundle exec crumbly-convert config/breadcrumbs.rb --namespace Admin \
  --output app/breadcrumbs/admin/breadcrumbs.rb --views app/views/admin
```

This writes `Admin::Breadcrumbs`, then prints each thing it left out or couldn't convert exactly, with its line.
You can pass several files (`config/breadcrumbs/*.rb`). They become one class, and when a crumb is defined twice
the later one wins, as in gretel.

| gretel | Crumbly |
|---|---|
| `crumb :key do \|order\| ... end` | `def key(order) ... end`; a parameter the crumb tests for nil gets `= nil` |
| `link label, url` | `crumb label, url`; `link label` or `link label, nil` give a level without a URL |
| a second `link` | `links: [link(label, url)]` on the same level |
| `parent :other, order` | `parent: other(order)` |
| `parent record` | `parent: crumb_for(record)` |
| `parent :a` and `parent :b` in an `if`/`else` | `parent: condition ? a : b` |
| `parent :a`, then `parent :b if condition` | `parent: condition ? b : a` |
| `link` and `parent` inside an `if`, `elsif`, `unless` or `case`, modifiers included | one `crumb` call per branch, with the statements after the conditional copied into each |
| view helpers such as `t(".x")` or `current_user` | `helpers.t(".x")`, `helpers.current_user`; route helpers stay as they are |
| `%i[a b].each { \|name\| crumb name do ... end }`, `{a: [:post, Comment]}.each { \|name, (parent, model)\| ... }` | one method per element |
| a local assigned before a crumb that reads it, such as `path = :"admin_#{name}_path"` | copied into each crumb that reads it; a literal is written in place |
| `label = ->(record) { ... }` at the top of the file, reading no other local | a private method: `label.call(post)` becomes `label(post)` |

Some things are listed for you to convert by hand:

- a loop over anything but a literal array or hash of symbols, strings, numbers and constants;
- `link` or `parent` inside a loop or a block;
- `link` options such as `title:` or `class:`;
- a crumb named after a Ruby keyword or an existing method (`display`, `test`);
- any statement that isn't a crumb, a loop or a local.

Comments are kept, above the method they came before.

The converter needs Prism 1.2 or later. Ruby 3.4 comes with it. On Ruby 3.3, add `gem "prism"` to the development
group.

### 2. Compare the trails

While gretel is still installed, your tests can draw every trail with both gems and list where the labels or URLs
differ. Keep gretel in the test group with `require: false`. `crumbly/oracle` loads it without gretel's view
helpers, whose `breadcrumb` would replace Crumbly's:

```ruby
# Gemfile, on the migration branch
gem "gretel", require: false, group: :test
```

Your views already call `breadcrumb` the way Crumbly expects, so your controller, integration and system tests can
do the comparing. With `Crumbly::Oracle.watch` in the test helper, gretel also draws each page the tests render,
from the same `breadcrumb` call:

```ruby
# test/test_helper.rb, once the app is loaded
require "crumbly/oracle"

Crumbly::Oracle.watch
Minitest.after_run do
  puts Crumbly::Oracle.differences.to_a, Crumbly::Oracle.redundant_calls.to_a
end
```

`differences` lists each page whose trail changed, with gretel's and Crumbly's side by side. It includes pages
with no `breadcrumb` call, which had no trail with gretel and get one now. gretel shows a crumb's extra links as
levels of their own, and the comparison does the same with `links`. A call that gretel can't draw is listed too,
with gretel's error.

`redundant_calls` lists the `breadcrumb` calls you can delete, because the page gets the same trail without them.
`watch { ... }` watches a block only.

Parallel test workers each keep their own lists, and `after_run` in the parent process doesn't see them. Run the
watched suite with `PARALLEL_WORKERS=1`.

For crumbs that no test renders, `compare` checks the calls you give it:

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

### 3. Review the calls in your views

The `--views` option of `crumbly-convert` lists the `breadcrumb` calls that Crumbly may now make unnecessary:
`:generic_form` (or `:new`, `:edit`) in new and edit views, `breadcrumb @order` in a show view, and
`breadcrumb :orders` in an index view. It doesn't delete anything. Remove a call once its page shows the same
trail without it; for the pages your tests render, `Crumbly::Oracle.redundant_calls` tells you which ones.

### 4. Remove gretel

Remove gretel and `config/breadcrumbs.rb`, and render `breadcrumb_trail` in the layout where `breadcrumbs` was.

## Performance

`bench/render.rb` renders the same five-level trail (Home > Customers > Alice > Orders > Order 2026-0042) with
gretel and with Crumbly, and checks that both give the same output. The `<ol>` row compares gretel's
`breadcrumbs(style: :ol)` with a ten-line helper over `breadcrumb_trail`. The JSON-LD row compares gretel's
`structured_data(url_base:)`, with paths behind a prefix, and `breadcrumb_json_ld` with `_url` helpers. Both are
encoded and escaped the same way.

Ruby 4.0.9, Rails 8.1.4, gretel 5.1.0, Apple M5 (arm64 macOS), median of three runs of benchmark-ips:

| Render | Allocations | Time, YJIT off | Time, YJIT on |
|---|---|---|---|
| gretel `<ol>` | 345 | 57.6 µs | 35.1 µs |
| Crumbly `<ol>` | 274 | 45.4 µs | 29.8 µs |
| gretel JSON-LD | 268 | 41.3 µs | 25.4 µs |
| Crumbly JSON-LD | 287 | 43.3 µs | 29.5 µs |

Crumbly's JSON-LD is a little slower, mostly because Rails' `_url` helpers are slower than `_path` ones. Building
the `BreadcrumbList` from the levels takes 1.7 µs of the difference.

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

Pull requests don't touch `CHANGELOG.md`. A release starts by writing its notes under `## [Unreleased]`, from the
pull requests merged since the last tag, without committing them. Then, from an up-to-date `main` with green CI:

```sh
bin/release minor --dry-run   # shows the notes and the changes, writes nothing
bin/release minor             # or patch, major, or an exact version such as 1.2.0
```

`main` takes no direct push. `bin/release` dates the Unreleased section and bumps the version on a branch named
`release/vX.Y.Z`, opens its pull request, which merges itself once CI is green, and waits for the merge. It then
pushes a signed tag `vX.Y.Z` on the merge commit. If you stopped it while it waited, `bin/release --tag X.Y.Z`
does this step. The tag starts the Release workflow, which publishes the gem to RubyGems through trusted
publishing and creates the GitHub release with the version's notes and the `.gem` file.

## License

MIT, by Level UP Solutions. The idea of a crumb that names its parent comes from
[gretel](https://github.com/kzkn/gretel), by Lasse Bunk and Kazuki Nishikawa.
