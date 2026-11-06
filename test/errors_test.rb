# frozen_string_literal: true

require "test_helper"

class ErrorsTest < ActiveSupport::TestCase
  class Reports
    attr_reader :errors

    def initialize
      @errors = []
    end

    def report(error, **)
      errors << error
    end
  end

  test "a crumb defined twice in a namespace raises when the class loads" do
    error = assert_raises(Crumbly::DuplicateCrumb) do
      Class.new(Crumbly::Trail) do
        def orders = crumb("Orders")
        def orders = crumb("All orders") # rubocop:disable Lint/DuplicateMethods -- the mistake under test
      end
    end
    assert_match "#orders is defined twice", error.message
  end

  test "a namespace may override a crumb it inherits" do
    base = Class.new(Crumbly::Trail) { def orders = crumb("Orders") }
    trail_class = Class.new(base) { def orders = crumb("All orders") }

    assert_equal ["All orders"], trail_class.resolve(nil, :orders).map(&:label)
  end

  test "private methods are helpers, not crumbs" do
    trail_class = Class.new(Crumbly::Trail) do
      def orders = crumb(label)

      private

      def label = "Orders"
    end

    assert trail_class.crumb?(:orders)
    refute trail_class.crumb?(:label)
    assert_raises(Crumbly::UnknownCrumb) { trail_class.resolve(nil, :label) }
  end

  test "an unknown crumb raises outside production" do
    error = assert_raises(Crumbly::UnknownCrumb) { Admin::Breadcrumbs.resolve(nil, :invoices) }
    assert_equal "Admin::Breadcrumbs has no crumb named invoices", error.message

    error = assert_raises(Crumbly::UnknownCrumb) { Admin::Breadcrumbs.resolve(nil, POST) }
    assert_equal "Admin::Breadcrumbs has no crumb for Post: define #post", error.message
  end

  test "an unknown crumb is reported in production and leaves the page without a trail" do
    reports = Reports.new
    ActiveSupport.error_reporter.subscribe(reports)
    Crumbly.raise_on_unknown_crumb = false

    assert_equal [], Admin::Breadcrumbs.resolve(nil, :invoices)
    assert_equal ["Admin::Breadcrumbs has no crumb named invoices"], reports.errors.map(&:message)
  ensure
    Crumbly.raise_on_unknown_crumb = nil
    ActiveSupport.error_reporter.unsubscribe(reports)
  end

  test "a view passing nil or an object without a model raises outside production" do
    error = assert_raises(Crumbly::UnknownCrumb) { Admin::Breadcrumbs.resolve(nil, nil) }
    assert_equal "Admin::Breadcrumbs has no crumb for nil: pass a crumb name or a record", error.message

    error = assert_raises(Crumbly::UnknownCrumb) { Admin::Breadcrumbs.resolve(nil, {"id" => "1"}) }
    assert_equal "Admin::Breadcrumbs has no crumb for a Hash: pass a crumb name or a record", error.message
  end

  test "a view passing nil is reported in production and leaves the page without a trail" do
    reports = Reports.new
    ActiveSupport.error_reporter.subscribe(reports)
    Crumbly.raise_on_unknown_crumb = false

    assert_equal [], Admin::Breadcrumbs.resolve(nil, nil)
    assert_equal ["Admin::Breadcrumbs has no crumb for nil: pass a crumb name or a record"], reports.errors.map(&:message)
  ensure
    Crumbly.raise_on_unknown_crumb = nil
    ActiveSupport.error_reporter.unsubscribe(reports)
  end

  test "a parent that is not a crumb raises, naming what it got" do
    trail_class = Class.new(Crumbly::Trail) do
      def orders = crumb("Orders")
      def order = crumb("Order", parent: :orders)
    end

    error = assert_raises(ArgumentError) { trail_class.resolve(nil, :order) }
    assert_equal "parent: takes a crumb, such as parent: orders, not :orders", error.message
  end

  test "a controller outside any namespace with breadcrumbs says where to define them" do
    controller_class = Class.new(ActionController::Base) { def self.name = "OrdersController" }
    error = assert_raises(Crumbly::MissingTrail) { Crumbly.trail_class_for(controller_class) }
    assert_match "define Breadcrumbs (a Crumbly::Trail)", error.message
  end

  test "breadcrumbs_with picks the namespace class explicitly" do
    controller_class = Class.new(ActionController::Base) { breadcrumbs_with Storefront::Breadcrumbs }

    assert_equal Storefront::Breadcrumbs, Crumbly.trail_class_for(controller_class)
  end
end
