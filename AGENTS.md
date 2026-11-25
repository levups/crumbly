# Crumbly

Breadcrumbs for Rails: one `Crumbly::Trail` class per namespace, trails derived from the routes, checked in tests
with `Crumbly.verify!`, and `crumbly-convert` plus `Crumbly::Oracle` to migrate from gretel.

`README.md` covers usage, `STYLE.md` code style, `CONTRIBUTING.md` contributions; this file adds what they leave out.

## Commands

```sh
bundle exec rake test                                            # the newest Rails (Gemfile)
BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle exec rake test  # the oldest maintained Rails
bundle exec rubocop
bundle exec ruby [--yjit] bench/render.rb                        # render time against gretel
```

CI also runs `ruby-head`, and every Ruby with each Gemfile. A new Rails gets a `gemfiles/rails_X_Y.gemfile` and
joins CI's `rails` matrix.

## Traps

- gretel and Prism stay out of the gemspec. `Crumbly::Oracle` needs gretel; the converter and the verifier need
  Prism 1.2+ (bundled from Ruby 3.4, `gem "prism"` on 3.3).
- A derived trail reads the record the controller already loaded (`@order`), never a query.
- An unknown crumb or a relative JSON-LD URL raises outside production and goes to `ActiveSupport.error_reporter`
  in production: test both paths.
- The README is the user guide and `docs/` the GitHub Pages site: change them with the code. The README's
  Performance table and `docs/benchmarks.html` come from the same `bench/render.rb` run.

## Rules for all our gems

This section and the next two read the same in super-slim, gamba, crumbly, agentry and maptain: change all five
together.

You are the owner and long-term maintainer of this codebase, and its design is up to you. Its public API is a
promise to its users; everything behind it is yours to reshape when that serves them.

- Every maintained Ruby and Rails (https://endoflife.date), nothing older. The oldest sets `required_ruby_version`,
  `TargetRubyVersion` and the Rails floor, and leaves in the release after its end of life.
- CI runs RuboCop and the tests on each maintained Ruby. No macOS job: we test on our Macs.
- `.claude/hooks/rubocop.sh` autocorrects each Ruby file you edit.
- Measure performance without JIT and with YJIT. A Performance cop the numbers contradict is disabled on its line,
  with the reason. A pure performance change pins no internals in tests.
- Test and bench data are anonymized: `alice`, `Post`, `example.com`.
- `docs/llms.txt` (an index for coding agents) and `docs/llms-full.txt` (the README and
  the pages of `docs/`, in Markdown) come from `bundle exec rake docs:llms`: run it after changing the README or a page of
  `docs/`. CI checks them.
- Everything in the repository is in English (code, comments, commits, pull requests, issues, reviews, replies),
  whatever the conversation's language.
- No AI attribution in anything people read; commits flag AI help with `Assisted-by`, never `Co-Authored-By`.

## Pull requests and issues

- `main` takes no direct push: every change, releases included, goes through a pull request that merges itself once
  CI is green (`gh pr merge --auto --squash`).
- Drafts run no CI. Confident: open it ready, auto-merge on. Not yet: a draft, then `gh pr ready` when it needs CI.
- Never edit `CHANGELOG.md` in a pull request, they would all conflict: it is written at release time.
- Title: the change as a user sees it (an issue: the finding), in plain words, under 70 characters.
- Body, no headings: two short paragraphs, the problem then the change (an issue: what to do); 3 to 5 bullets, each
  opening with a **bold 2–4 word lead-in**; the proof (reproduction, tests, benchmarks) folded in one `<details>`.
  Nothing the diff or CI already says.
- Never hard-wrap a pull request, an issue or a comment: GitHub renders every line break. One line per paragraph and
  per bullet.

## Releases

The user is needed once: one click approving the `release` environment on GitHub. No key, no Mac.

1. Another session may have just released: `git fetch --tags origin`, and `gh pr list --search "head:release/"`
   must be empty. Unreleased changes: `git log --first-parent --oneline $(git describe --tags --abbrev=0 origin/main)..origin/main`,
   then `gh pr view <n>` for each.
2. Write the release under `## [Unreleased]` in `CHANGELOG.md`, uncommitted: a one-sentence lede, then **Breaking**,
   **New**, **Faster** (measured), **Fixed**, only those with entries. One entry per change users see, written for
   them; CI, refactoring, docs and tests get none. No version, date or link: `bin/release` adds them.
3. Show it to the user, wait for their go. From `main` level with `origin/main`, `CHANGELOG.md` its only change:
   `bin/release minor --dry-run`, then `bin/release minor --yes` (or `patch`, `major`). It opens `release/vX.Y.Z`,
   waits for it to merge itself, then opens the release run. Interrupted: `bin/release --wait X.Y.Z`. Where `gh pr`
   can't run, `bin/release minor --write` writes the changes: commit them, open the pull request with auto-merge.
4. The merge runs `release.yml`, which waits for the user to approve the `release` environment, then tags the merge
   commit `vX.Y.Z` and publishes to RubyGems and GitHub. Send them the run's link, where they click Review
   deployments, `release`, Approve (from their phone too). Then check RubyGems. A failed run runs again from its page,
   or with `gh workflow run release.yml`: each step skips what is done.

Only a merged pull request publishes: a version with notes in `CHANGELOG.md` and no tag yet. RubyGems trusts only
that workflow: never `gem push`, except a new gem name's first version, pushed by hand while its run waits for
approval. `bin/release` and `release.yml` are identical in all five gems.
