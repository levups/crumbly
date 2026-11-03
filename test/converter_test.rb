# frozen_string_literal: true

require "test_helper"
require "gretel/ngg/converter"

class ConverterTest < ActiveSupport::TestCase
  FIXTURES = File.expand_path("fixtures", __dir__)

  test "a gretel breadcrumbs file becomes a Trail class, and what is left out is listed with its line" do
    result = Gretel::Ngg::Converter.call({"config/breadcrumbs.rb" => File.read("#{FIXTURES}/gretel_breadcrumbs.rb")},
      namespace: "Converted")

    assert_equal File.read("#{FIXTURES}/converted_breadcrumbs.rb"), result.ruby
    assert_equal [
      "config/breadcrumbs.rb:7: crumb :orders is defined again on config/breadcrumbs.rb:89, which gretel kept: left out",
      "config/breadcrumbs.rb:72: crumb :help: link options target: \"_blank\" have no equivalent in Gretel NGG: left out",
      "config/breadcrumbs.rb:77: crumb :order_items calls link or parent inside " \
      "order.items.each { |item| link item.n...: left out, convert it by hand",
      "config/breadcrumbs.rb:81: not a crumb definition, left out: REPORTS = %i[margins taxes].freeze",
      "config/breadcrumbs.rb:83: crumbs defined in a loop over REPORTS, which is not a literal: left out, " \
      "write them by hand"
    ], result.notes.map(&:to_s)
  end

  test "several links: the first is the crumb, the others its extra links" do
    assert_crumb <<~RUBY, <<~GRETEL
      def order(order)
        crumb order.to_s, [:admin, order],
          links: [link("Invoice", nil), link("Shipment", "/shipments")]
      end
    RUBY
      crumb :order do |order|
        link order.to_s, [:admin, order]
        link "Invoice"
        link "Shipment", "/shipments"
      end
    GRETEL
  end

  test "a crumb that only sets a parent is its parent, and one that sets nothing has no level" do
    assert_crumb <<~RUBY, <<~GRETEL
      def dashboard
        orders
      end

      def blank
      end
    RUBY
      crumb :dashboard do
        parent :orders
      end

      crumb :blank do
      end
    GRETEL
  end

  test "links set before a conditional reach each of its branches" do
    assert_crumb <<~RUBY, <<~GRETEL
      def report(report)
        if report.daily?
          crumb report.name, parent: daily_reports
        elsif report.weekly?
          crumb report.name, parent: weekly_reports
        else
          crumb report.name
        end
      end
    RUBY
      crumb :report do |report|
        link report.name
        if report.daily?
          parent :daily_reports
        elsif report.weekly?
          parent :weekly_reports
        end
      end
    GRETEL
  end

  test "unless becomes if when it has an else, and a parent set on one side only stays a modifier" do
    assert_crumb <<~RUBY, <<~GRETEL
      def invoice(invoice = nil)
        if invoice
          crumb "Invoice", parent: invoices
        else
          crumb "Invoices"
        end
      end

      def refund(refund)
        crumb "Refund", parent: (invoice(refund.invoice) unless refund.manual?)
      end
    RUBY
      crumb :invoice do |invoice|
        unless invoice
          link "Invoices"
        else
          link "Invoice"
          parent :invoices
        end
      end

      crumb :refund do |refund|
        link "Refund"
        parent :invoice, refund.invoice unless refund.manual?
      end
    GRETEL
  end

  test "view helpers go through helpers, a parent named like a local goes through self" do
    assert_crumb <<~RUBY, <<~GRETEL
      def account(orders)
        crumb helpers.t(".account", count: orders.size), account_path(helpers.current_user),
          parent: self.orders
      end
    RUBY
      crumb :account do |orders|
        link t(".account", count: orders.size), account_path(current_user)
        parent :orders
      end
    GRETEL
  end

  test "an array of pairs looped over expands into one crumb per pair" do
    assert_crumb <<~RUBY, <<~GRETEL
      def sales_report
        crumb "Sales", parent: reports
      end

      def stock_report
        crumb "Stock", parent: reports
      end
    RUBY
      [[:sales, "Sales"], [:stock, "Stock"]].each do |name, label|
        crumb :"\#{name}_report" do
          link label
          parent :reports
        end
      end
    GRETEL
  end

  test "a crumb a Trail cannot hold is listed, with the line inside its loop" do
    result = Gretel::Ngg::Converter.call({"breadcrumbs.rb" => <<~GRETEL})
      %i[display orders].each do |name|
        crumb name do
          link name.to_s
        end
      end
    GRETEL

    assert_equal ["breadcrumbs.rb:2: crumb :display cannot be a method of a Trail: rename it (name = :display)"],
      result.notes.map(&:to_s)
    assert_includes result.ruby, "def orders\n    crumb \"orders\"\n  end"
  end

  test "a file Ruby cannot parse raises with its line" do
    error = assert_raises(ArgumentError) { Gretel::Ngg::Converter.call({"breadcrumbs.rb" => "crumb :a do\n"}) }
    assert_match(/\Abreadcrumbs.rb:\d+: /, error.message)
  end

  private

  def assert_crumb(expected, gretel)
    result = Gretel::Ngg::Converter.call({"breadcrumbs.rb" => gretel})

    assert_empty result.notes.map(&:to_s)
    expected_class = "# frozen_string_literal: true\n\nclass Breadcrumbs < Gretel::Ngg::Trail\n" \
                     "#{expected.gsub(/^(?=.)/, "  ")}end\n"
    assert_equal expected_class, result.ruby
  end
end
