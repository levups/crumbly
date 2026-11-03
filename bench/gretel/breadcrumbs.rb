# frozen_string_literal: true

crumb :root do
  link "Home", root_path
end

crumb :customers do
  link "Customers", customers_path
end

crumb :customer do |customer|
  link customer.to_s, customer_path(customer)
  parent :customers
end

crumb :customer_orders do |customer|
  link "Orders", customer_orders_path(customer)
  parent :customer, customer
end

crumb :order do |order|
  link order.to_s, customer_order_path(order.customer, order)
  parent :customer_orders, order.customer
end
