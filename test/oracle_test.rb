# frozen_string_literal: true

require "test_helper"
require "rails"
require "gretel"
require "gretelx/oracle"
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

    assert_empty GretelX::Oracle.compare(@view, Converted::Breadcrumbs, cases).map(&:to_s)
  end

  test "a difference shows both trails" do
    differences = GretelX::Oracle.compare(@view, Admin::Breadcrumbs, [[:customer, ALICE], [:order_messages, ORDER]])

    assert_equal [<<~TEXT.chomp], differences.map(&:to_s)
      breadcrumb :order_messages, #<Order 42>
        gretel:     Home (/admin) > Alice (/admin/customers/7) > Order 2026-0042 (/admin/orders/42) > Invoice (/admin/orders/42/invoice.pdf) > Messages (/admin/orders/42/messages)
        gretelx: Home (/admin) > Orders (/admin/orders) > Order 2026-0042 (/admin/orders/42) > Invoice (/admin/orders/42/invoice.pdf) > Messages (/admin/orders/42/messages)
    TEXT
  end
end
