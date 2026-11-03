# frozen_string_literal: true

source "https://rubygems.org"

gemspec

rails_version = ENV.fetch("RAILS_VERSION", "8.1")

group :development, :test do
  gem "actionpack", "~> #{rails_version}.0"
  gem "activemodel", "~> #{rails_version}.0"
  gem "activesupport", "~> #{rails_version}.0"
  gem "gretel"
  gem "minitest"
  gem "prism", ">= 1.2"
  gem "rake"
  gem "rubocop", require: false
  gem "rubocop-performance", require: false
  gem "standard", require: false
end
