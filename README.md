# Gretel NGG

Breadcrumbs for Rails: namespaced, derived from your routes, checked in tests.

[gretel](https://github.com/kzkn/gretel) works, but on a real back office (one file of about 1,000 lines,
265 crumbs, 380 call sites), its shape is what hurts:

- one global file and one flat namespace, where a crumb defined twice silently replaces the first, and an
  admin area cannot keep its breadcrumbs apart from a storefront's;
- mistakes that only show when someone opens the page;
- blocks run through `instance_exec` and helpers reached through `method_missing`;
- every trail written by hand, even when the routes already describe it.

Gretel NGG keeps gretel's good idea (a crumb names its parent) and changes the rest:

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
gem "gretel-ngg"
```

The railtie adds `breadcrumb` and `breadcrumb_trail` to your views, and `breadcrumbs_with` to your controllers.

## Usage

```ruby
# app/breadcrumbs/admin/breadcrumbs.rb
module Admin
  class Breadcrumbs < Gretel::Ngg::Trail
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
- Every name that works in a view is a crumb, so `Gretel::Ngg::Trail` keeps its own methods private. The ones
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
| `new`, `create` | « New » (`gretel_ngg.new`) under the collection |
| `edit`, `update` | « Edit » (`gretel_ngg.edit`) under the record |

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
# Gretel NGG, app/breadcrumbs/admin/breadcrumbs.rb: optional, the nested route derives the same trail
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
# Gretel NGG
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
  parent order.customer ? [:customer_orders, order.customer] : :orders
end
```

```ruby
# Gretel NGG
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
# Gretel NGG
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
# Gretel NGG: nothing to write. new and edit derive « New » under the collection, « Edit » under the record.
```

## Checked in tests

A crumb defined twice already raises when its class loads. One test checks the rest, without running a crumb
or loading a record:

```ruby
# test/breadcrumbs_test.rb
require "test_helper"
require "gretel/ngg/test_helper"

class BreadcrumbsTest < ActiveSupport::TestCase
  test "breadcrumbs" do
    assert_breadcrumbs_valid
  end
end
```

It eager-loads the app and reads the source of every crumb (and of the private helpers next to it) with Prism:

- every parent a crumb calls is a crumb, and every `_path` or `_url` it calls is a route helper;
- every `breadcrumb :name` in `app/views` and `app/controllers` names a crumb some trail defines;
- every crumb is reachable: called by another crumb, by a view or controller (`breadcrumb :name`,
  `breadcrumb @record`), by a derived trail (the collection and record of a routed controller), or named after
  a model. The others are dead, and fail the test.

`Gretel::Ngg.verify!` does the same outside Minitest: it raises `Gretel::Ngg::InvalidTrail` with every problem
in one message, and returns the dead crumbs (`["Admin::Breadcrumbs#drafts"]`). Both take `trail_classes:`,
`routes:` and `sources:` (the directories scanned for `breadcrumb` calls).

## Storefronts

The trail is data, so absolute URLs are just `_url` helpers in that namespace's crumbs:

```ruby
module Storefront
  class Breadcrumbs < Gretel::Ngg::Trail
    def category(category)
      crumb category.name, storefront_category_url(category),
        parent: category.parent ? category(category.parent) : shop
    end
  end
end
```

## Roadmap

- A JSON-LD `BreadcrumbList` helper for storefronts.
- A codemod from gretel's `config/breadcrumbs.rb`.

## Requirements

Ruby 3.3 or later, and Rails 8.0 or later (Action Pack and Active Support).

## License

MIT, by Level UP Solutions.
