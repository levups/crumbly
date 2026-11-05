# GretelX

Breadcrumbs for Rails (gem `gretelx`, module `GretelX`): one `GretelX::Trail` class per namespace, trails derived
from the routes, checked in tests (`GretelX.verify!`), plus `gretelx-convert` and `GretelX::Oracle` to migrate from
gretel. By Level UP Solutions, in the next-gen-gems organization. The README is the user documentation, `docs/` the
GitHub Pages site: keep both in step with the code. `CHANGELOG.md` is written when releasing (Changelog and
releases).

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
Rails gets `gemfiles/rails_X_Y.gemfile` and joins the CI's `rails` matrix.

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

- Never edit `CHANGELOG.md` in a PR: any two PRs adding a line there conflict. The changelog is written when
  releasing, from the PRs merged since the last tag; a PR title says what changes for users.
- A draft runs no CI, so it never turns green. Confident in the change: open the pull request ready for review,
  auto-merge on. Not yet: a draft, then `gh pr ready` when it needs the CI.
- To release, read every PR merged since the last tag (`git log --first-parent --oneline <tag>..origin/main`,
  squash merges end in `(#n)`, then `gh pr view n`), and write the release under `## [Unreleased]` without
  committing it: a one-sentence lede, then **Breaking**, **New**, **Faster** (measured, with and without YJIT)
  and **Fixed**, only those with entries. One entry per change users can see, written for them: several PRs may
  make one, CI, refactoring, docs and tests make none. Show it to the user, then `bin/release` commits it with
  the version. No version heading, date or link by hand: `bin/release` writes them.
- `main` takes no direct push, ours included: every change, a release too, goes through a pull request that merges
  itself once the required CI checks are green (`gh pr merge --auto --squash`).
- `bin/release patch|minor|major` cuts a release from a green, up-to-date `main` through such a pull request, then
  tags its merge commit (README, Releasing), and `.github/workflows/release.yml` publishes it. Both are the same in
  every next-gen-gems gem: change them in all four at once.
- RubyGems trusts the Release workflow (trusted publishing): never `gem push` from a machine.

## Pull requests and issues

- Title: the change as a user sees it (an issue: the finding), in plain words, under 70 characters.
- Body, no headings: two short paragraphs, the problem then the change (an issue: what to do); 3 to 5 bullets,
  each a **bold 2–4 word lead-in** and two lines at most (decisions, divergences, what is left out); the proof
  (reproduction, tests, fuzz seeds, benchmarks) folded in one `<details>`. Nothing the diff or the CI says.
