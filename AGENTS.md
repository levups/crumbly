# Crumbly

Breadcrumbs for Rails: one `Crumbly::Trail` class per namespace, trails derived from the routes, checked in tests
with `Crumbly.verify!`, and `crumbly-convert` plus `Crumbly::Oracle` to migrate from gretel.

Read `README.md` for usage, `STYLE.md` for code style and `CONTRIBUTING.md` for contributions; this file only
adds what they leave out.

## Commands

```sh
bundle exec rake test                                            # the newest Rails (Gemfile)
BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle exec rake test  # the oldest maintained Rails
bundle exec rubocop
bundle exec ruby [--yjit] bench/render.rb                        # render time against gretel
```

CI also runs `ruby-head`, and every Ruby with each Gemfile. A new Rails gets a `gemfiles/rails_X_Y.gemfile` and
joins the `rails` matrix in CI.

## Traps

- gretel and Prism are not runtime dependencies: keep them out of the gemspec. `Crumbly::Oracle` needs gretel; the
  converter and the verifier need Prism 1.2+ (bundled from Ruby 3.4, `gem "prism"` on 3.3).
- A derived trail reads the record the controller already loaded (`@order`), never a query.
- An unknown crumb or a relative JSON-LD URL raises outside production and goes to `ActiveSupport.error_reporter`
  in production: test both paths.
- The README is the user guide and `docs/` the GitHub Pages site: change them with the code. The README's
  Performance table and `docs/benchmarks.html` come from the same `bench/render.rb` run.

## Rules for all our gems

This section and the next two read the same in super-slim, gamba, crumbly and agentry: change all four together.

- Every maintained Ruby and Rails (https://endoflife.date), nothing older. The oldest sets `required_ruby_version`,
  `TargetRubyVersion` and the Rails floor, and leaves in the release after its end of life.
- CI runs RuboCop and the tests on each maintained Ruby. No macOS job: we test on our Macs.
- `.claude/hooks/rubocop.sh` autocorrects each Ruby file you edit.
- Measure performance without JIT and with YJIT. A Performance cop the numbers contradict is disabled on its line,
  with the reason. A pure performance change pins no internals in tests.
- Test and bench data are anonymized: `alice`, `Post`, `example.com`.
- Everything in the repository is in English (code, comments, commits, pull requests, issues, reviews, replies),
  whatever the language of the conversation.
- No AI attribution in anything people read.

## Pull requests and issues

- `main` takes no direct push. Every change, releases included, goes through a pull request that merges itself
  once CI is green: `gh pr merge --auto --squash`.
- Drafts run no CI. Confident in the change? Open it ready for review, auto-merge on. Not yet? Open a draft, then
  `gh pr ready` when it needs CI.
- Never edit `CHANGELOG.md` in a pull request: they would all conflict. It is written at release time.
- Title: the change as a user sees it (for an issue, the finding), in plain words, under 70 characters.
- Body, no headings: two short paragraphs, the problem then the change (for an issue, what to do); 3 to 5 bullets,
  each opening with a **bold 2–4 word lead-in**; the proof (reproduction, tests, benchmarks) folded in one
  `<details>`. Nothing the diff or CI already says.
- Never hard-wrap a pull request, an issue or a comment: GitHub renders every line break. One line per paragraph
  and per bullet.

## Releases

1. List the pull requests merged since the last tag: `git log --first-parent --oneline <tag>..origin/main`, then
   `gh pr view <n>` for each.
2. Write the release under `## [Unreleased]` in `CHANGELOG.md`, uncommitted: a one-sentence lede, then
   **Breaking**, **New**, **Faster** (measured) and **Fixed**, only those with entries. One entry per change users
   can see, written for them; CI, refactoring, docs and tests get none. No version, date or link: `bin/release`
   adds them.
3. Show it to the user. Then `bin/release patch|minor|major` (try `--dry-run` first) commits it through a pull
   request, waits for the merge and tags it; the tag runs `.github/workflows/release.yml`, which publishes the gem.

RubyGems trusts only that workflow: never `gem push` from a machine, except the very first version of a new gem
name. `bin/release` and `release.yml` are the same in all four gems.
