# frozen_string_literal: true

require_relative "lib/crumbly/version"

Gem::Specification.new do |spec|
  spec.name = "crumbly"
  spec.version = Crumbly::VERSION
  spec.authors = ["Level UP Solutions"]
  spec.summary = "Breadcrumbs for Rails: namespaced, derived from your routes, checked in tests"
  spec.description = "One class of plain Ruby methods per namespace, a trail derived from the controller and " \
                     "the routes when a view says nothing, mistakes raised when the class loads, and the trail " \
                     "returned as data for your own components."
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
  spec.add_dependency "loofah", ">= 2.21"
end
