# frozen_string_literal: true

require "test_helper"
require "crumbly/converter"

class ConverterTest < ActiveSupport::TestCase
  FIXTURES = File.expand_path("fixtures", __dir__)

  test "a gretel breadcrumbs file becomes a Trail class, and what is left out is listed with its line" do
    result = Crumbly::Converter.call({"config/breadcrumbs.rb" => File.read("#{FIXTURES}/gretel_breadcrumbs.rb")},
      namespace: "Converted")

    assert_equal File.read("#{FIXTURES}/converted_breadcrumbs.rb"), result.ruby
    assert_equal [
      "config/breadcrumbs.rb:7: crumb :orders is defined again on config/breadcrumbs.rb:89, which gretel kept: left out",
      "config/breadcrumbs.rb:72: crumb :help: link options target: \"_blank\" have no equivalent in Crumbly: left out",
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

  test "a parent set under a condition falls back on the parent set before it" do
    assert_crumb <<~RUBY, <<~GRETEL
      def comment(comment)
        crumb comment.to_s,
          parent: comment.reply? ? comment(comment.parent) : (post(comment.post) if comment.post)
      end

      def note(note)
        crumb "Note",
          parent: note.private? ? notes : (note.archived? ? archive : (order(note.order) if note.order))
      end
    RUBY
      crumb :comment do |comment|
        link comment.to_s
        parent :post, comment.post if comment.post
        parent :comment, comment.parent if comment.reply?
      end

      crumb :note do |note|
        link "Note"
        parent :order, note.order if note.order
        if note.archived?
          parent :archive
        end
        parent :notes if note.private?
      end
    GRETEL
  end

  test "a condition that binds looser than the ternary is parenthesised" do
    assert_crumb <<~RUBY, <<~GRETEL
      def note(note)
        crumb "Note",
          parent: (note.draft? or note.hidden?) ? drafts : ((not note.public?) ? private_notes : notes)
      end

      def reply(reply)
        crumb "Reply", parent: (comment = reply.comment) ? comment(comment) : comments
      end
    RUBY
      crumb :note do |note|
        link "Note"
        parent :notes
        parent :private_notes if not note.public?
        parent :drafts if note.draft? or note.hidden?
      end

      crumb :reply do |reply|
        link "Reply"
        if comment = reply.comment
          parent :comment, comment
        else
          parent :comments
        end
      end
    GRETEL
  end

  test "a local assigned by the condition of a parent is assigned before it is read" do
    assert_crumb <<~RUBY, <<~GRETEL
      def note(note)
        crumb "Note",
          parent: (owner_name = note.owner&.model_name&.singular) ? public_send(owner_name.to_sym, note.owner) : nil
      end
    RUBY
      crumb :note do |note|
        link "Note"
        if (owner_name = note.owner&.model_name&.singular)
          parent owner_name.to_sym, note.owner
        end
      end
    GRETEL
  end

  test "a conditional before other statements takes them into each of its branches" do
    assert_crumb <<~RUBY, <<~GRETEL
      def comment(comment)
        if comment.new_record?
          crumb "New comment", parent: (post(comment.post) if comment.post)
        else
          crumb comment.to_s, [:admin, comment], parent: (post(comment.post) if comment.post)
        end
      end

      def reports(author = nil)
        if author
          crumb author.name, [:admin, author], parent: posts, links: [link("Reports", nil)]
        else
          crumb "Reports", parent: posts
        end
      end
    RUBY
      crumb :comment do |comment|
        if comment.new_record?
          link "New comment"
        else
          link comment.to_s, [:admin, comment]
        end
        parent :post, comment.post if comment.post
      end

      crumb :reports do |author|
        link author.name, [:admin, author] if author
        link "Reports"
        parent :posts
      end
    GRETEL
  end

  test "a case becomes one crumb call per branch" do
    assert_crumb <<~RUBY, <<~GRETEL
      def returns(owner = nil)
        case owner
        when Order, Invoice
          crumb "Returns", [:admin, owner, :returns], parent: crumb_for(owner)
        when Customer
          crumb "Returns", admin_customer_returns_path(owner), parent: customer(owner)
        else
          crumb "Returns", admin_returns_path
        end
      end

      def notes(owner = nil)
        case owner
        when Post
          crumb "Notes", parent: post(owner)
        end
      end
    RUBY
      crumb :returns do |owner = nil|
        case owner
        when Order, Invoice
          link "Returns", [:admin, owner, :returns]
          parent owner
        when Customer
          link "Returns", admin_customer_returns_path(owner)
          parent :customer, owner
        else
          link "Returns", admin_returns_path
        end
      end

      crumb :notes do |owner|
        case owner
        when Post
          link "Notes"
          parent :post, owner
        end
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

  test "a loop may destructure its pairs, and yield constants" do
    assert_crumb <<~RUBY, <<~GRETEL
      def post_comments(record)
        crumb Comment.model_name.human, parent: post(record)
      end

      def order_notes(record)
        crumb Admin::Note.model_name.human, parent: order(record)
      end
    RUBY
      {post_comments: [:post, Comment], order_notes: [:order, Admin::Note]}.each do |name, (parent_name, model)|
        crumb name do |record|
          link model.model_name.human
          parent parent_name, record
        end
      end
    GRETEL
  end

  test "a local a crumb reads is copied into its method, a literal written in place, a lambda made a method" do
    assert_crumb <<~RUBY, <<~GRETEL
      def drafts
        label = title(:drafts)
        crumb label, admin_drafts_path, parent: posts
      end

      def archives
        label = title(:archives)
        crumb label, admin_archives_path, parent: posts
      end

      private

      # Drafts, Archives
      def title(name)
        name.to_s.humanize
      end
    RUBY
      # Drafts, Archives
      title = ->(name) { name.to_s.humanize }
      parent_name = :posts

      %i[drafts archives].each do |name|
        path = :"admin_\#{name}_path"
        label = title.call(name)
        crumb name do
          link label, public_send(path)
          parent parent_name
        end
      end
    GRETEL
  end

  test "a lambda reading other locals, or with numbered parameters, is copied; one read as a value is a method" do
    result = Crumbly::Converter.call({"breadcrumbs.rb" => <<~GRETEL})
      prefix = "Admin"
      name = "top"
      short = -> { _1.to_s }
      titled = ->(text) { "\#{prefix} \#{text}" }
      upcased = ->(text) { text.upcase }
      crumb :tags do |post|
        link post.tags.map { |name| name.upcase }.join, "/tags"
        link post.tags.map(&upcased).join
        link titled.call(short.call(post))
      end
      name = "again"
    GRETEL

    assert_equal <<~RUBY, result.ruby
      # frozen_string_literal: true

      class Breadcrumbs < Crumbly::Trail
        def tags(post)
          short = -> { _1.to_s }
          titled = ->(text) { "\#{"Admin"} \#{text}" }
          crumb post.tags.map { |name| name.upcase }.join, "/tags",
            links: [link(post.tags.map(&method(:upcased)).join, nil), link(titled.call(short.call(post)), nil)]
        end

        private

        def upcased(text)
          text.upcase
        end
      end
    RUBY
    assert_equal ["breadcrumbs.rb:11: name is assigned again: a crumb above that reads it gets its first value, " \
                  "where gretel read the last one"], result.notes.map(&:to_s)
  end

  test "a crumb a Trail cannot hold is listed, with the line inside its loop" do
    result = Crumbly::Converter.call({"breadcrumbs.rb" => <<~GRETEL})
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
    error = assert_raises(ArgumentError) { Crumbly::Converter.call({"breadcrumbs.rb" => "crumb :a do\n"}) }
    assert_match(/\Abreadcrumbs.rb:\d+: /, error.message)
  end

  private

  def assert_crumb(expected, gretel)
    result = Crumbly::Converter.call({"breadcrumbs.rb" => gretel})

    assert_empty result.notes.map(&:to_s)
    expected_class = "# frozen_string_literal: true\n\nclass Breadcrumbs < Crumbly::Trail\n" \
                     "#{expected.gsub(/^(?=.)/, "  ")}end\n"
    assert_equal expected_class, result.ruby
  end
end
