# frozen_string_literal: true

module Converted
  class Breadcrumbs < GretelX::Trail
    def root
      crumb "Home", admin_root_path
    end

    # An order links to its invoice from the same level.
    def order(order)
      crumb "Order #{order.number}", admin_order_path(order),
        parent: order.customer ? customer(order.customer) : orders,
        links: [link("Invoice", "/admin/orders/#{order.id}/invoice.pdf")]
    end

    def order_messages(order)
      crumb "Messages", admin_order_messages_path(order), parent: order(order)
    end

    def customer(customer)
      crumb customer.name, [:admin, customer]
    end

    def returns(owner = nil)
      if owner
        crumb "Returns", [:admin, owner, :returns], parent: crumb_for(owner)
      else
        crumb "Returns", admin_returns_path
      end
    end

    def categories
      crumb "Categories", admin_categories_path
    end

    def category(category, ancestors = category.ancestors.to_a)
      *grandparents, parent_category = ancestors
      crumb category.name, admin_category_path(category),
        parent: parent_category ? category(parent_category, grandparents) : categories
    end

    def generic_form(model)
      if model.new_record?
        crumb "New", parent: public_send(model.class.model_name.plural.to_sym)
      else
        crumb "Edit", parent: crumb_for(model)
      end
    end

    def posts
      crumb "Posts", admin_posts_path
    end

    def categories_report
      crumb "Category report", admin_categories_report_path
    end

    def sales_report
      crumb "#{"sales".capitalize} report"
    end

    def stock_report
      crumb "#{"stock".capitalize} report"
    end

    def help
      crumb "Help", "https://example.com/help"
    end

    def orders
      crumb helpers.t("admin.orders", default: "All orders"), admin_orders_path
    end

    def order_notes(order)
      crumb label_for("Internal notes"), admin_order_notes_path(order), parent: order(order)
    end

    def order_shipments(order)
      crumb label_for(:shipments), admin_order_shipments_path(order), parent: order(order)
    end

    private

    def label_for(label)
      label.is_a?(Symbol) ? label.to_s.humanize : label
    end
  end
end
