# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "actionpack"
  gem "activemodel"
  gem "activesupport"
  gem "gretel"
  gem "minitest"
  gem "prism", ">= 1.2"
  gem "rake"
  gem "rubocop", require: false
  gem "rubocop-performance", require: false
  gem "standard", require: false
end

group :development do
  gem "benchmark-ips", require: false
  gem "rouge", "5.1.0" # pinned: docs:highlight:check compares its output with the committed pages
end
