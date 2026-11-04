# frozen_string_literal: true

crumb :root do
  link "Home", admin_root_path
end

crumb :orders do
  link "Orders", admin_orders_path
end

# An order links to its invoice from the same level.
crumb :order do |order|
  link "Order #{order.number}", admin_order_path(order)
  link "Invoice", "/admin/orders/#{order.id}/invoice.pdf"
  if order.customer
    parent :customer, order.customer
  else
    parent :orders
  end
end

crumb :order_messages do |order|
  link "Messages", admin_order_messages_path(order)
  parent :order, order
end

crumb :customer do |customer|
  link customer.name, [:admin, customer]
end

crumb :returns do |owner|
  if owner
    link "Returns", [:admin, owner, :returns]
    parent owner
  else
    link "Returns", admin_returns_path
  end
end

crumb :categories do
  link "Categories", admin_categories_path
end

crumb :category do |category, ancestors = category.ancestors.to_a|
  link category.name, admin_category_path(category)
  *grandparents, parent_category = ancestors
  parent_category ? parent(:category, parent_category, grandparents) : parent(:categories)
end

crumb :generic_form do |model|
  if model.new_record?
    link "New", nil
    parent model.class.model_name.plural.to_sym
  else
    link "Edit", nil
    parent model
  end
end

{posts: "Posts", categories_report: "Category report"}.each do |name, label|
  crumb name do
    link label, send("admin_#{name}_path")
  end
end

%i[sales stock].each do |report|
  crumb :"#{report}_report" do
    link "#{report.to_s.capitalize} report"
  end
end

crumb :help do
  link "Help", "https://example.com/help", target: "_blank"
end

crumb :order_items do |order|
  order.items.each { |item| link item.name, admin_order_path(order) }
  parent :order, order
end

REPORTS = %i[margins taxes].freeze

REPORTS.each do |report|
  crumb report do
    link report.to_s.capitalize
  end
end

crumb :orders do
  link t("admin.orders", default: "All orders"), admin_orders_path
end

label_for = ->(label) { label.is_a?(Symbol) ? label.to_s.humanize : label }

{order_notes: [:order, "Internal notes"], order_shipments: [:order, :shipments]}.each do |name, (parent_name, label)|
  path = :"admin_#{name}_path"
  crumb name do |order|
    link label_for.call(label), public_send(path, order)
    parent parent_name, order
  end
end
