# frozen_string_literal: true

require "test_helper"
require "rails"
require "gretel"
require "crumbly/oracle"
require_relative "fixtures/converted_breadcrumbs"

class OracleTest < ActiveSupport::TestCase
  setup do
    Gretel.breadcrumb_paths = [File.expand_path("fixtures/gretel_breadcrumbs.rb", __dir__)]
    Gretel::Crumbs.load_breadcrumbs
    controller = Admin::OrdersController.new
    controller.request = ActionDispatch::TestRequest.create
    @view = controller.view_context
  end

  teardown do
    Gretel.reset!
  end

  test "the converted file draws the trails gretel drew" do
    cases = [
      [:orders], [:order, ORDER], [ORDER], [:order_messages, ORDER], [:customer, ALICE], [:returns],
      [:returns, ORDER], [:returns, ALICE], [:category, NOVELS], [:posts], [:sales_report], [:help],
      [:order_notes, ORDER], [:order_shipments, ORDER]
    ]

    assert_empty Crumbly::Oracle.compare(@view, Converted::Breadcrumbs, cases).map(&:to_s)
  end

  test "a difference shows both trails" do
    differences = Crumbly::Oracle.compare(@view, Admin::Breadcrumbs, [[:customer, ALICE], [:order_messages, ORDER]])

    assert_equal [<<~TEXT.chomp], differences.map(&:to_s)
      breadcrumb :order_messages, #<Order 42>
        gretel:     Home (/admin) > Alice (/admin/customers/7) > Order 2026-0042 (/admin/orders/42) > Invoice (/admin/orders/42/invoice.pdf) > Messages (/admin/orders/42/messages)
        crumbly: Home (/admin) > Orders (/admin/orders) > Order 2026-0042 (/admin/orders/42) > Invoice (/admin/orders/42/invoice.pdf) > Messages (/admin/orders/42/messages)
    TEXT
  end
end

class OracleWatchTest < IntegrationTestCase
  setup do
    Gretel.breadcrumb_paths = [File.expand_path("fixtures/gretel_breadcrumbs.rb", __dir__)]
    Crumbly::Oracle.differences.clear
    Crumbly::Oracle.redundant_calls.clear
  end

  teardown do
    Gretel.reset!
  end

  test "each trail the tests render is compared with gretel's, and a call the action derives anyway is listed" do
    Crumbly::Oracle.watch do
      get "/admin/orders/42/messages"
      get "/admin/categories/3"
      get "/admin/categories/3"
      get "/admin/posts"
    end

    assert_equal [<<~TEXT.chomp, <<~TEXT.chomp], Crumbly::Oracle.differences.map(&:to_s)
      admin/messages#index, breadcrumb :order_messages, #<Order 42>
        gretel:     Home (/admin) > Alice (/admin/customers/7) > Order 2026-0042 (/admin/orders/42) > Invoice (/admin/orders/42/invoice.pdf) > Messages (/admin/orders/42/messages)
        crumbly: Home (/admin) > Orders (/admin/orders) > Order 2026-0042 (/admin/orders/42) > Invoice (/admin/orders/42/invoice.pdf) > Messages (/admin/orders/42/messages)
    TEXT
      admin/posts#index, no breadcrumb call
        gretel:     (none)
        crumbly: Home (/admin) > Posts (/admin/posts)
    TEXT
    assert_equal ["admin/categories#show, breadcrumb #<Category 3>: the action derives the same trail"],
      Crumbly::Oracle.redundant_calls.map(&:to_s)
  end

  test "with derive_trails false, no call is redundant and a page without one matches gretel's empty trail" do
    Crumbly::Oracle.watch do
      get "/backstage/categories/3"
      get "/backstage/posts"
    end

    assert_empty Crumbly::Oracle.differences
    assert_empty Crumbly::Oracle.redundant_calls
  end

  test "outside the block, nothing is compared" do
    Crumbly::Oracle.watch {}
    get "/admin/orders/42/messages"

    assert_empty Crumbly::Oracle.differences
  end

  test "a call gretel cannot draw is a difference" do
    Gretel.breadcrumb_paths = [File.expand_path("fixtures/gretel_root_only.rb", __dir__)]
    controller = Admin::OrdersController.new
    controller.request = ActionDispatch::TestRequest.create
    controller.action_name = "show"
    view = controller.view_context
    Crumbly::Oracle.observe(view, [:order_notes, [ORDER]], Admin::Breadcrumbs.resolve(view, :order_notes, ORDER))

    assert_equal ["admin/orders#show, breadcrumb :order_notes, #<Order 42>\n  gretel:     gretel raised " \
                  "ArgumentError: Breadcrumb :order_notes not found.\n  crumbly: Home (/admin) > Orders (/admin/orders) > " \
                  "Order 2026-0042 (/admin/orders/42) > Invoice (/admin/orders/42/invoice.pdf) > " \
                  "Internal notes (/admin/orders/42/notes)"],
      Crumbly::Oracle.differences.map(&:to_s)
  end
end
