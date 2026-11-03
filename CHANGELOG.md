# Changelog

## Unreleased

- One `Gretel::Ngg::Trail` subclass per namespace (`Admin::Breadcrumbs`, `Storefront::Breadcrumbs`), found from
  the controller's module; one public method per crumb, its parent a plain method call.
- A view that names no crumb gets the trail of its action, derived from the routes and the controller's record.
- Derived trails follow nested routes: each `:<name>_id` path parameter is a parent level, built from the record
  the controller loaded (`@order`) and never queried. A namespace crumb named after the nesting
  (`order_messages`) takes precedence; the order of precedence (view, namespace crumb, derived) is documented.
- A crumb defined twice raises when the class loads; an unknown crumb raises outside production and is reported
  through `ActiveSupport.error_reporter` in production.
- `breadcrumb_trail` returns data (`label`, `url`, `links`, `current?`) for the app's own components.
- `Gretel::Ngg.verify!` and `assert_breadcrumbs_valid` (`require "gretel/ngg/test_helper"`) check every trail
  from its source: unknown parents, unknown route helpers and views calling an undefined crumb raise together in
  `Gretel::Ngg::InvalidTrail`; dead crumbs are returned, and fail the assertion.
- `breadcrumb_json_ld` renders the trail as a schema.org `BreadcrumbList` for Google's rich results (plain-text
  names, JSON escaped for a `<script>` tag); a relative URL raises `Gretel::Ngg::RelativeUrl` outside production
  and is reported in production. `Gretel::Ngg::JsonLd.call(levels)` returns it as a hash.
- `bench/render.rb` measures a render against gretel on the same trail.
