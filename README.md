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

## Why Crumbly

Crumbly was written to replace [gretel](https://github.com/kzkn/gretel) in a back office with 265 crumbs, in one
file of about 1,000 lines, and 380 calls in views. It works differently in a few ways:

- The crumbs of each part of the app live in their own class, `Admin::Breadcrumbs` or `Storefront::Breadcrumbs`,
  so the admin and the storefront can both have an `orders` crumb.
- A crumb is a plain method. Route helpers work in it as in a view, and a backtrace points at its line.
- Index, show, new and edit pages get their trail from the routes and the record the controller loaded, so most
  views name no crumb.
- One test reads every crumb and fails on a parent, a route helper or a crumb name that doesn't exist, without
  touching the database.
- The trail comes back as data, and your layout writes the HTML. The gem has no styles or rendering options.
- Rendering a five-level trail as an `<ol>` takes 45.4 µs against 57.6 µs for gretel, with 274 allocations
  instead of 345 (YJIT off). JSON-LD is a little slower: see [Performance](#performance).

Its runtime dependencies are Action Pack, Active Support and Loofah, which Rails already installs.

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

On the page of an order whose `to_s` is "Order 42", with the admin routes at `/admin`, this writes:

```html
<nav aria-label="Breadcrumb">
  <ol>
    <li><a href="/admin">Home</a></li>
    <li><a href="/admin/orders">Orders</a></li>
    <li>Order 42</li>
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
level without a link. A string is used as it is, so if it comes from your users, check its scheme first: a
`javascript:` URL in a link runs a script.

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

To raise in production too, on a staging server for example, set it in an initializer:

```ruby
Crumbly.raise_on_unknown_crumb = true
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

## Switching from gretel, loaf or breadcrumbs_on_rails

Crumbly uses the same view helper names as these gems, so an app switches in one go: there is no compatibility
layer, and the old gem leaves the Gemfile once the migration is merged.

From gretel, the calls in your views barely change (`breadcrumb :order, @order` and `breadcrumb @order` work as
before), and `crumbly-convert` turns `config/breadcrumbs.rb` into a trail class:

```sh
bundle exec crumbly-convert config/breadcrumbs.rb --namespace Admin \
  --output app/breadcrumbs/admin/breadcrumbs.rb --views app/views/admin
```

It prints each line it left out or couldn't convert exactly, and with `--views`, the `breadcrumb` calls that
Crumbly may now make unnecessary. It needs Prism 1.2 or later: Ruby 3.4 comes with it, and on Ruby 3.3 you add
`gem "prism"` to the development group. While gretel is still installed on the migration branch,
`Crumbly::Oracle` draws each trail your tests render with both gems and lists where the labels or URLs differ.

The [migration guide](https://levups.github.io/crumbly/migration.html) has every step: what the converter maps to
what, what it leaves to you, the comparison in your tests, and the same walk-through for loaf and
breadcrumbs_on_rails. The [home page](https://levups.github.io/crumbly/) shows five crumbs from a real gretel app
next to their Crumbly version.

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

## How Crumbly is tested

CI runs the test suite on Ruby 3.3, 3.4 and 4.0, each against Rails 8.0 and 8.1, and on `ruby-head`. The
tests convert a sample gretel file, compare the result with the expected class line for line, then draw its trails
with gretel and with the converted class and check that the labels and URLs match. The production paths (an unknown crumb, a relative JSON-LD URL) are tested
as well as the raising ones.

## Development

```sh
bundle install
bundle exec rake test                                            # latest Rails
BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle exec rake test  # Rails 8.0
bundle exec rubocop
bundle exec rake docs:highlight                                  # after editing a code block in docs/
```

[CONTRIBUTING.md](CONTRIBUTING.md) says what a pull request needs.

### Releasing

Pull requests don't touch `CHANGELOG.md`. A release starts by writing its notes under `## [Unreleased]`, from the
pull requests merged since the last tag, without committing them. Then, from an up-to-date `main` with green CI:

```sh
bin/release minor --dry-run   # shows the notes and the changes, writes nothing
bin/release minor             # or patch, major, or an exact version such as 1.2.0
```

`bin/release` bumps the version on a `release/vX.Y.Z` branch, opens its pull request, waits for it to merge
itself once CI is green, and pushes a signed tag `vX.Y.Z` on the merge commit (`bin/release --tag X.Y.Z` resumes
this step if you stopped it). The tag starts the Release workflow, which publishes the gem to RubyGems through
trusted publishing and creates the GitHub release.

## License

MIT, by Level UP Solutions. The idea of a crumb that names its parent comes from
[gretel](https://github.com/kzkn/gretel), by Lasse Bunk and Kazuki Nishikawa.
