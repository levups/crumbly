# Changelog

## [Unreleased]

## [2.2.0] — 2026-11-06

A trail class can turn off derived trails with `derive_trails false`, and a derived level labels a record without its own `to_s` "Invoice 12" instead of `#<Invoice:0x…>`.

**New**
- `derive_trails false` in a trail class, for apps that want only the trails they write, as with gretel: a view without a `breadcrumb` call gets an empty `breadcrumb_trail` and a nil `breadcrumb_json_ld`. Subclasses inherit it and `derive_trails true` turns it back on. In such a class, `Crumbly.verify!` reports a crumb that only a derived trail would read as unused, and `Crumbly::Oracle.redundant_calls` lists nothing.

**Fixed**
- A derived level whose record's model doesn't define `to_s` is labelled with the translated model name and id, "Invoice 12", instead of Ruby's `#<Invoice:0x000…>`. A model's own `to_s` still wins.

## [2.1.0] — 2026-11-06

Crumbs refuse `javascript:`, `vbscript:` and `data:` URLs, and a nil record, odd bytes or `=begin` comments no longer break Crumbly.

**New**
- `Crumbly::UnsafeUrl`, for a crumb or a `link` whose URL is `javascript:`, `vbscript:` or `data:`, in any case and with the spaces, control characters, tabs and line breaks that browsers drop. It raises in development and test; in production it goes to `Rails.error`, and the level keeps its label without the link. `Crumbly.raise_on_unsafe_url` chooses, like the other two settings.

**Fixed**
- loofah's floor moves to 2.25.3, and with it nokogiri's to 1.19.5: the first versions without the 2026 advisories, two of them in the HTML5 scrubber Crumbly calls on `html_safe` labels.
- `breadcrumb` with a nil record, or an object without a model, raises or reports `Crumbly::UnknownCrumb` instead of a `NoMethodError` that failed the page. A `parent:` that is not a crumb raises an `ArgumentError` that names it.
- `breadcrumb_json_ld` replaces invalid bytes in a label with U+FFFD, and reads `HTTPS://` as an absolute URL.
- `Crumbly.verify!` and `crumbly-convert --views` read files that are not UTF-8 instead of crashing.
- `crumbly-convert` writes `=begin` comments as `#` lines, and keeps a loop value interpolated in a regexp, a command, a `%W` array or `%Q/`, where it wrote Ruby that doesn't parse.

## [2.0.0] — 2026-11-05

GretelX is now Crumbly, in the levups organization: same breadcrumbs, new names.

**Breaking**
- The gem is `gem "crumbly"`: `require "crumbly"`, `require "crumbly/test_helper"` and `require "crumbly/oracle"` replace their gretelx versions.
- The module `GretelX` becomes `Crumbly` (`Crumbly::Trail`, `Crumbly.verify!`, `Crumbly::Oracle`, `Crumbly::InvalidTrail`, `Crumbly::RelativeUrl`), and its i18n keys `gretelx.new` / `gretelx.edit` become `crumbly.new` / `crumbly.edit`.
- The executable `gretelx-convert` becomes `crumbly-convert`.

## [1.1.0] — 2026-11-04

The app's own test suite becomes the migration oracle, `verify!` catches crumbs called with the wrong number of
arguments, and `crumbly-convert` converts the conditionals and loops it used to leave out or get wrong.

**New**
- `Crumbly::Oracle.watch`, in the test helper of a migrating app, compares with gretel every trail the tests
  render: changed trails go to `Oracle.differences` with their page, including pages without a `breadcrumb` call
  that now derive a trail, and calls the action would derive anyway go to `Oracle.redundant_calls`. `watch { ... }`
  limits it to a block; run the watched suite with `PARALLEL_WORKERS=1`. `crumbly/oracle` now requires gretel, so
  the app can bundle it with `require: false`.
- `Crumbly.verify!` reports crumbs called with the wrong number of arguments, by another crumb or by a
  `breadcrumb :name, ...` in a view (`app/views/orders/index.html.erb:1 calls breadcrumb :orders with 1
  argument, which takes 0`): gretel dropped or defaulted them to `nil`, a converted crumb raises `ArgumentError`.

**Fixed**
- `crumbly-convert` converts a `link` or `parent` in any conditional, `case`/`when` included, followed by more
  statements: each branch ends with its own crumb call. A `parent` set under a condition keeps the one set before
  it, and a condition that assigns a local no longer raises `NameError` on the first render.
- `crumbly-convert` expands loops that destructure their pairs or list constants, copies into each crumb the
  locals it reads (a literal `path` is written in place, so `verify!` can check it), and turns a lambda assigned
  at the top of the file into a private method of the Trail. `parent parent_name` with a literal local now calls
  the crumb (`posts`) instead of `crumb_for(:posts)`.

## [1.0.0] — 2026-11-04

First release: breadcrumbs for Rails, trails defined in Ruby classes or derived from the routes, checked in
tests. Replaces gretel: `crumbly-convert` turns its breadcrumbs files into Crumbly classes.

**New**
- One `Crumbly::Trail` subclass per namespace (`Admin::Breadcrumbs`, `Storefront::Breadcrumbs`), found from
  the controller's module; one public method per crumb, its parent a plain method call.
- A view that names no crumb gets the trail of its action, derived from the routes and the controller's record.
- Derived trails follow nested routes: each `:<name>_id` path parameter is a parent level, built from the record
  the controller loaded (`@order`) and never queried. A namespace crumb named after the nesting
  (`order_messages`) takes precedence; the order of precedence (view, namespace crumb, derived) is documented.
- A crumb defined twice raises when the class loads; an unknown crumb raises outside production and is reported
  through `ActiveSupport.error_reporter` in production.
- `breadcrumb_trail` returns data (`label`, `url`, `links`, `current?`) for the app's own components.
- `Crumbly.verify!` and `assert_breadcrumbs_valid` (`require "crumbly/test_helper"`) check every trail
  from its source: unknown parents, unknown route helpers and views calling an undefined crumb raise together in
  `Crumbly::InvalidTrail`; dead crumbs are returned, and fail the assertion.
- `breadcrumb_json_ld` renders the trail as a schema.org `BreadcrumbList` for Google's rich results (plain-text
  names, JSON escaped for a `<script>` tag); a relative URL raises `Crumbly::RelativeUrl` outside production
  and is reported in production. `Crumbly::JsonLd.call(levels)` returns it as a hash.
- `bench/render.rb` measures a render against gretel on the same trail.
- `crumbly-convert` turns gretel's breadcrumbs files into a `Crumbly::Trail` class, expanding crumbs
  defined in loops over literals and listing, with their line, what it does not convert. `--views` lists the
  `breadcrumb` calls a derived trail may now cover.
- `Crumbly::Oracle.compare` draws trails with gretel and with Crumbly, from a test of an app migrating.

[Unreleased]: https://github.com/levups/crumbly/compare/v2.2.0...HEAD
[2.2.0]: https://github.com/levups/crumbly/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/levups/crumbly/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/levups/crumbly/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/levups/crumbly/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/levups/crumbly/releases/tag/v1.0.0
