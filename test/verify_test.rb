# frozen_string_literal: true

require "test_helper"
require "gretel/ngg/test_helper"
require "tmpdir"

module Checked
  class UnknownParent < Gretel::Ngg::Trail
    def orders
      crumb "Orders", admin_orders_path
    end

    def order(order)
      crumb order.to_s, admin_order_path(order), parent: order_list
    end
  end

  class UnknownRouteHelper < Gretel::Ngg::Trail
    def orders
      crumb "Orders", admin_order_list_path
    end
  end

  class DeadCrumb < Gretel::Ngg::Trail
    def orders
      crumb "Orders", admin_orders_path
    end

    def archived_orders
      crumb "Archived", admin_orders_path, parent: orders
    end
  end

  class CalledFromHelper < Gretel::Ngg::Trail
    def orders
      crumb "Orders", admin_orders_path
    end

    def archived_orders
      crumb "Archived", admin_orders_path, parent: orders
    end

    private

    def collection_crumb
      archived_orders
    end
  end
end

class VerifyTest < ActiveSupport::TestCase
  VIEWS = {
    "admin/messages/index.html.erb" => "<% breadcrumb :order_messages, @order %>",
    "admin/returns/index.html.erb" => "<% breadcrumb(:returns, owner) %>",
    "admin/reports/sales.html.erb" => "<% breadcrumb \"sales_report\" %>",
    "admin/categories/show.html.erb" => "<% breadcrumb @category %>"
  }.freeze

  test "every crumb, parent, route helper and view call checks out" do
    with_views(VIEWS) do |views|
      assert_equal [], Gretel::Ngg.verify!(trail_classes: [Admin::Breadcrumbs, Storefront::Breadcrumbs], sources: [views])
      assert_breadcrumbs_valid(trail_classes: [Admin::Breadcrumbs, Storefront::Breadcrumbs], sources: [views])
    end
  end

  test "an unknown parent" do
    error = assert_raises(Gretel::Ngg::InvalidTrail) { verify(Checked::UnknownParent) }
    assert_match(/Checked::UnknownParent#order calls order_list, which is not a crumb \(.*verify_test.rb:14\)/,
      error.message)
  end

  test "an unknown route helper" do
    error = assert_raises(Gretel::Ngg::InvalidTrail) { verify(Checked::UnknownRouteHelper) }
    assert_match "Checked::UnknownRouteHelper#orders calls admin_order_list_path, which is not a route helper",
      error.message
  end

  test "a crumb called from a view but never defined" do
    with_views("admin/invoices/index.html.erb" => "<h1>Invoices</h1>\n<% breadcrumb :invoices %>") do |views|
      error = assert_raises(Gretel::Ngg::InvalidTrail) { verify(Checked::DeadCrumb, sources: [views]) }
      assert_match "admin/invoices/index.html.erb:2 calls breadcrumb :invoices, which no trail defines", error.message
    end
  end

  test "every problem in one message" do
    error = assert_raises(Gretel::Ngg::InvalidTrail) { verify(Checked::UnknownParent, Checked::UnknownRouteHelper) }
    assert_match(/\A2 breadcrumb problem\(s\):\n- .*order_list.*\n- .*admin_order_list_path/, error.message)
  end

  test "a dead crumb is listed, and fails the assertion" do
    assert_equal ["Checked::DeadCrumb#archived_orders"], verify(Checked::DeadCrumb)

    failure = assert_raises(Minitest::Assertion) { assert_breadcrumbs_valid(trail_classes: [Checked::DeadCrumb], sources: []) }
    assert_match "Dead crumbs, called by no crumb, view or controller: Checked::DeadCrumb#archived_orders", failure.message
  end

  test "a crumb is alive when a view, or a private helper of its trail, calls it" do
    with_views("admin/orders/archived.html.erb" => "<% breadcrumb :archived_orders %>") do |views|
      assert_equal [], verify(Checked::DeadCrumb, sources: [views])
    end
    assert_equal [], verify(Checked::CalledFromHelper)
  end

  private

  def verify(*trail_classes, sources: [])
    Gretel::Ngg.verify!(trail_classes:, sources:)
  end

  def with_views(views)
    Dir.mktmpdir do |directory|
      views.each do |path, source|
        FileUtils.mkdir_p(File.dirname(File.join(directory, path)))
        File.write(File.join(directory, path), source)
      end
      yield directory
    end
  end
end
