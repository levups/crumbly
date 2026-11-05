# frozen_string_literal: true

require "test_helper"

class JsonLdTest < IntegrationTestCase
  def level(label, url, current: false)
    Crumbly::Level.new(label:, url:, links: [], current:)
  end

  test "a BreadcrumbList with positions from 1 and the current level last" do
    breadcrumb_list = Crumbly::JsonLd.call([
      level("Shop", "https://example.com/"),
      level("Books", "https://example.com/categories/1"),
      level("Fiction", "https://example.com/categories/2", current: true)
    ])

    assert_equal(
      {
        "@context" => "https://schema.org",
        "@type" => "BreadcrumbList",
        "itemListElement" => [
          {"@type" => "ListItem", "position" => 1, "name" => "Shop", "item" => "https://example.com/"},
          {"@type" => "ListItem", "position" => 2, "name" => "Books", "item" => "https://example.com/categories/1"},
          {"@type" => "ListItem", "position" => 3, "name" => "Fiction", "item" => "https://example.com/categories/2"}
        ]
      },
      breadcrumb_list
    )
  end

  test "the current level may have no URL, a level above it without one is left out" do
    breadcrumb_list = Crumbly::JsonLd.call([
      level("Shop", "https://example.com/"),
      level("Reports", nil),
      level("Sales", nil, current: true)
    ])

    assert_equal(
      [
        {"@type" => "ListItem", "position" => 1, "name" => "Shop", "item" => "https://example.com/"},
        {"@type" => "ListItem", "position" => 2, "name" => "Sales"}
      ],
      breadcrumb_list["itemListElement"]
    )
  end

  test "a name is plain text: markup is stripped from html_safe labels, kept as text otherwise" do
    label = ActiveSupport::SafeBuffer.new('<i class="icon"></i> Tom &amp; Jerry <script>alert(1)</script>')
    breadcrumb_list = Crumbly::JsonLd.call([
      level(label, "https://example.com/tom-and-jerry"),
      level("Alice's <b>orders</b>", "https://example.com/orders", current: true)
    ])

    assert_equal ["Tom & Jerry", "Alice's <b>orders</b>"], breadcrumb_list["itemListElement"].map { |item| item["name"] }
  end

  test "an empty trail has no BreadcrumbList" do
    assert_nil Crumbly::JsonLd.call([])
  end

  test "a relative URL raises outside production" do
    error = assert_raises(Crumbly::RelativeUrl) do
      Crumbly::JsonLd.call([level("Orders", "/orders"), level("Order 2026-0042", nil, current: true)])
    end
    assert_equal 'JSON-LD needs absolute URLs: "Orders" links to /orders, use a _url helper in its crumb',
      error.message
  end

  test "a relative URL is reported in production and leaves the page without a BreadcrumbList" do
    Crumbly.raise_on_relative_url = false

    assert_error_reported(Crumbly::RelativeUrl) do
      assert_nil Crumbly::JsonLd.call([level("Orders", "/orders", current: true)])
    end
  ensure
    Crumbly.raise_on_relative_url = nil
  end

  test "breadcrumb_json_ld renders a script that a label cannot close" do
    get "/storefront/search", params: {q: "</script><script>alert(1)</script>"}

    assert_response :success
    assert_equal '<script type="application/ld+json">', response.body[0, 35]
    assert_equal 1, response.body.scan("</script>").size
    json = response.body.delete_prefix('<script type="application/ld+json">').delete_suffix("</script>")
    assert_equal(
      [
        {"@type" => "ListItem", "position" => 1, "name" => "Shop", "item" => "http://www.example.com/storefront"},
        {"@type" => "ListItem", "position" => 2, "name" => "Search: </script><script>alert(1)</script>",
         "item" => "http://www.example.com/storefront/search?q=%3C%2Fscript%3E%3Cscript%3Ealert%281%29%3C%2Fscript%3E"}
      ],
      JSON.parse(json)["itemListElement"]
    )
  end
end
