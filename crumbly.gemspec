# frozen_string_literal: true

require_relative "lib/crumbly/version"

Gem::Specification.new do |spec|
  spec.name = "crumbly"
  spec.version = Crumbly::VERSION
  spec.authors = ["Level UP Solutions"]
  spec.summary = "Breadcrumb trails for Rails, written as plain Ruby methods and checked in tests"
  spec.description = "Each level of a breadcrumb trail is a Ruby method that names its parent. When a view names " \
                     "no crumb, Crumbly works the trail out from the controller and the routes, and one test " \
                     "checks every trail in the app. The trail comes back as data, so your layout writes the HTML."
  spec.homepage = "https://github.com/levups/crumbly"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://levups.github.io/crumbly/"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.files = Dir["lib/**/*.rb", "exe/*", "LICENSE", "README.md", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = ["crumbly-convert"]
  spec.require_paths = ["lib"]

  spec.add_dependency "actionpack", ">= 8.0"
  spec.add_dependency "activesupport", ">= 8.0"
  spec.add_dependency "loofah", ">= 2.25.3"
end
