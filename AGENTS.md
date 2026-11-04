# GretelX

Breadcrumbs for Rails (gem `gretelx`, module `GretelX`): one `GretelX::Trail` class per namespace, trails derived
from the routes, checked in tests (`GretelX.verify!`), plus `gretelx-convert` and `GretelX::Oracle` to migrate from
gretel. By Level UP Solutions, in the next-gen-gems organization. The README is the user documentation, `docs/` the
GitHub Pages site: keep both in step with the code. A user-visible change goes in an `## Unreleased` section on top
of `CHANGELOG.md`, added if missing.

## Compatibility

Every Ruby and Rails still maintained (endoflife.date), nothing older: today Ruby 3.3, 3.4, 4.0 and Rails 8.0, 8.1.
The oldest sets `required_ruby_version`, `TargetRubyVersion` and the Action Pack / Active Support floor in the
gemspec; Ruby 3.3 means no bare `it` (use `_1`). A version leaves in the release after its end of life.

## Commands

```sh
bundle exec rake test                                            # latest Rails (Gemfile)
BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle exec rake test  # Rails 8.0
bundle exec rubocop                                              # Standard's rules + every rubocop-performance cop
bundle exec ruby [--yjit] bench/render.rb                        # render against gretel
```

CI (`.github/workflows/ci.yml`) runs RuboCop, then every maintained Ruby and ruby-head times each Gemfile. A new
Rails gets `gemfiles/rails_X_Y.gemfile` and joins the CI's Gemfile list.

## Traps

- gretel and Prism are not runtime dependencies: `GretelX::Oracle` needs gretel, the converter and the verifier need
  Prism 1.2+ (bundled from Ruby 3.4, `gem "prism"` on 3.3). Keep them out of the gemspec.
- A derived trail reads the record the controller already loaded (`@order`), never a query.
- An unknown crumb or a relative JSON-LD URL raises outside production and goes to `ActiveSupport.error_reporter`
  in production: keep both paths tested.
- A hot-path change is measured with `bench/render.rb`, without JIT and with YJIT, and the README's Performance table
  and `docs/benchmarks.html` come from the same run. A pure performance change never pins internals in tests.
- Test and bench data stay generic (`Alice`, `Order 2026-0042`, `example.com`).
- `.claude/hooks/rubocop.sh` autocorrects each Ruby file after an edit.

## Code style

Follow `STYLE.md` (naming, method size, comments, dead code): what RuboCop can't settle.

## Changelog and releases

- Every user-visible change adds its line under `## [Unreleased]` in `CHANGELOG.md`, in the same PR. A release
  opens with a one-sentence lede, then **Breaking**, **New**, **Faster** (measured, with and without YJIT) and
  **Fixed**, only those with entries. No version heading, date or link by hand: `bin/release` writes them.
- `bin/release patch|minor|major` cuts a release from a green, up-to-date `main` (README, Releasing), and
  `.github/workflows/release.yml` publishes it. Both are the same in every next-gen-gems gem: change them in all
  four at once.
- RubyGems trusts the Release workflow (trusted publishing): never `gem push` from a machine.
