# Changelog

## Unreleased

- One `Gretel::Ngg::Trail` subclass per namespace (`Admin::Breadcrumbs`, `Storefront::Breadcrumbs`), found from
  the controller's module; one public method per crumb, its parent a plain method call.
- A view that names no crumb gets the trail of its action, derived from the routes and the controller's record.
- A crumb defined twice raises when the class loads; an unknown crumb raises outside production and is reported
  through `ActiveSupport.error_reporter` in production.
- `breadcrumb_trail` returns data (`label`, `url`, `links`, `current?`) for the app's own components.
- `gretel-ngg-convert` turns gretel's breadcrumbs files into a `Gretel::Ngg::Trail` class, expanding crumbs
  defined in loops over literals and listing, with their line, what it does not convert. `--views` lists the
  `breadcrumb` calls a derived trail may now cover.
- `Gretel::Ngg::Oracle.compare` draws trails with gretel and with Gretel NGG, from a test of an app migrating.
