# frozen_string_literal: true

require "test_helper"

class TrailTest < IntegrationTestCase
  test "a nested resource walks up through its parents, root first" do
    assert_trail "Home|/admin > Orders|/admin/orders > Order 2026-0042|/admin/orders/42|Invoice > " \
                 "Messages|/admin/orders/42/messages|current",
      "/admin/orders/42/messages"
  end

  test "a polymorphic parent is the crumb of the record's model" do
    assert_trail "Home|/admin > Orders|/admin/orders > Order 2026-0042|/admin/orders/42|Invoice > " \
                 "Returns|/admin/orders/42/returns|current",
      "/admin/orders/42/returns"
    assert_trail "Home|/admin > Alice|/admin/customers/7 > Returns|/admin/customers/7/returns|current",
      "/admin/customers/7/returns"
    assert_trail "Home|/admin > Returns|/admin/returns|current", "/admin/returns"
  end

  test "a recursive tree is a crumb calling itself" do
    assert_trail "Home|/admin > Categories|/admin/categories > Books|/admin/categories/1 > " \
                 "Fiction|/admin/categories/2 > Novels|/admin/categories/3|current",
      "/admin/categories/3"
  end

  test "a level without a URL" do
    assert_trail "Home|/admin > Sales|current", "/admin/reports/sales"
  end

  test "each namespace has its own crumbs under the same names" do
    assert_trail "Shop|http://www.example.com/storefront > " \
                 "Books|http://www.example.com/storefront/categories/1 > " \
                 "Fiction|http://www.example.com/storefront/categories/2|current",
      "/storefront/categories/2"
  end

  test "a view that names no crumb gets the crumb of its action" do
    assert_trail "Home|/admin > Orders|/admin/orders|current", "/admin/orders"
    assert_trail "Home|/admin > Orders|/admin/orders > Order 2026-0042|/admin/orders/42|current|Invoice",
      "/admin/orders/42"
  end

  test "a trail derived from the routes and the controller's record when no crumb is written" do
    assert_trail "Home|/admin > Posts|/admin/posts|current", "/admin/posts"
    assert_trail "Home|/admin > Posts|/admin/posts > Hello|/admin/posts/5|current", "/admin/posts/5"
    assert_trail "Home|/admin > Posts|/admin/posts > New|current", "/admin/posts/new"
    assert_trail "Home|/admin > Posts|/admin/posts > Hello|/admin/posts/5 > Edit|current", "/admin/posts/5/edit"
  end

  test "a nested route derives each parent from the record its controller loaded" do
    assert_trail "Home|/admin > Posts|/admin/posts > Hello|/admin/posts/5 > " \
                 "Comments|/admin/posts/5/comments|current",
      "/admin/posts/5/comments"
    assert_trail "Home|/admin > Posts|/admin/posts > Hello|/admin/posts/5 > " \
                 "Comments|/admin/posts/5/comments > First!|/admin/posts/5/comments/9|current",
      "/admin/posts/5/comments/9"
    assert_trail "Home|/admin > Posts|/admin/posts > Hello|/admin/posts/5 > " \
                 "Comments|/admin/posts/5/comments > First!|/admin/posts/5/comments/9 > " \
                 "Replies|/admin/posts/5/comments/9/replies|current",
      "/admin/posts/5/comments/9/replies"
  end

  test "a parent record the controller did not load ends the trail at its collection" do
    assert_trail "Home|/admin > Posts|/admin/posts > Replies|/admin/posts/5/comments/9/replies|current",
      "/admin/posts/5/comments/9/replies?without_post=1"
  end

  test "the view's crumb wins over the namespace's crumb named after the controller, which wins over derivation" do
    assert_trail "Home|/admin > Sales|current", "/admin/orders/42/notes?breadcrumb=sales_report"
    assert_trail "Home|/admin > Orders|/admin/orders > Order 2026-0042|/admin/orders/42|Invoice > " \
                 "Internal notes|/admin/orders/42/notes|current",
      "/admin/orders/42/notes"
    assert_trail "Home|/admin > Orders|/admin/orders > Order 2026-0042|/admin/orders/42|Invoice > " \
                 "Shipments|/admin/orders/42/shipments|current",
      "/admin/orders/42/shipments"
  end

  test "a record without its own to_s is named after its model and id" do
    assert_trail "Home|/admin > Invoices|/admin/invoices > Invoice 12|/admin/invoices/12|current", "/admin/invoices/12"
    assert_trail "Home|/admin > Invoices|/admin/invoices > Invoice 12|/admin/invoices/12 > " \
                 "Payments|/admin/invoices/12/payments|current",
      "/admin/invoices/12/payments"
  end

  test "the model name of a record without its own to_s is translated" do
    I18n.backend.store_translations(:en, activemodel: {models: {invoice: {one: "Bill", other: "Bills"}}})

    assert_trail "Home|/admin > Bills|/admin/invoices > Bill 12|/admin/invoices/12|current", "/admin/invoices/12"
  ensure
    I18n.reload!
  end

  test "with derive_trails false, a view that names no crumb has no trail, and one that does keeps it" do
    assert_trail "[] nil", "/backstage/posts"
    assert_trail "Home|/admin > Categories|/admin/categories > Books|/admin/categories/1 > " \
                 "Fiction|/admin/categories/2 > Novels|/admin/categories/3|current",
      "/backstage/categories/3"
  end

  test "derive_trails is inherited, can be turned back on, and is not a crumb" do
    assert Admin::Breadcrumbs.derive_trails?
    assert_not Backstage::Breadcrumbs.derive_trails?
    assert_not Class.new(Backstage::Breadcrumbs).derive_trails?
    assert Class.new(Backstage::Breadcrumbs) { derive_trails true }.derive_trails?
    assert_not Backstage::Breadcrumbs.crumb?(:derive_trails)

    error = assert_raises(ArgumentError) { Class.new(Crumbly::Trail) { derive_trails nil } }
    assert_equal "derive_trails takes true or false, not nil", error.message
  end
end
