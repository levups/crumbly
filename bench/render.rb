# frozen_string_literal: true

# bundle exec ruby [--yjit] bench/render.rb
# The same five-level trail (Home > Customers > Alice > Orders > Order 2026-0042) rendered by gretel and by
# Crumbly, as an <ol> of links and as a JSON-LD BreadcrumbList.

require "bundler/setup"
require "benchmark/ips"
require "rails"
require "action_controller"
require "active_model"
require "gretel"
require "crumbly"

ROUTES = ActionDispatch::Routing::RouteSet.new
ROUTES.draw do
  root "home#show"
  resources :customers, only: %i[index show] do
    resources :orders, only: %i[index show]
  end
end
ROUTES.default_url_options = {host: "example.com", protocol: "https"}

Gretel.breadcrumb_paths = [File.expand_path("gretel/breadcrumbs.rb", __dir__)]
Gretel.reload_environments = []
Crumbly.routes = ROUTES

class Record
  include ActiveModel::Model
  include ActiveModel::Conversion

  attr_accessor :id

  def persisted?
    true
  end
end

class Customer < Record
  attr_accessor :name

  def to_s
    name
  end
end

class Order < Record
  attr_accessor :number, :customer

  def to_s
    "Order #{number}"
  end
end

ALICE = Customer.new(id: 7, name: "Alice")
ORDER = Order.new(id: 42, number: "2026-0042", customer: ALICE)

module Admin
  class Breadcrumbs < Crumbly::Trail
    def root
      crumb "Home", root_path
    end

    def customers
      crumb "Customers", customers_path
    end

    def customer(customer)
      crumb customer.to_s, customer_path(customer), parent: customers
    end

    def customer_orders(customer)
      crumb "Orders", customer_orders_path(customer), parent: customer(customer)
    end

    def order(order)
      crumb order.to_s, customer_order_path(order.customer, order), parent: customer_orders(order.customer)
    end
  end
end

module Storefront
  class Breadcrumbs < Crumbly::Trail
    def root
      crumb "Home", root_url
    end

    def customers
      crumb "Customers", customers_url
    end

    def customer(customer)
      crumb customer.to_s, customer_url(customer), parent: customers
    end

    def customer_orders(customer)
      crumb "Orders", customer_orders_url(customer), parent: customer(customer)
    end

    def order(order)
      crumb order.to_s, customer_order_url(order.customer, order), parent: customer_orders(order.customer)
    end
  end
end

module CrumblyRendering
  def crumbly_breadcrumbs
    tag.ol(class: "breadcrumbs") do
      safe_join(breadcrumb_trail.map do |level|
        level.current? ? tag.li(level.label, class: "current") : tag.li(link_to(level.label, level.url))
      end)
    end
  end
end

module GretelRendering
  def gretel_json_ld
    breadcrumb_list = breadcrumbs.structured_data(url_base: "https://example.com")
    tag.script(ERB::Util.json_escape(JSON.generate(breadcrumb_list)).html_safe, type: "application/ld+json")
  end
end

class BenchController < ActionController::Base
  include ROUTES.url_helpers
  include Crumbly::Controller
end

class GretelController < BenchController
  helper Gretel::ViewHelpers, GretelRendering
end

module Admin
  class CrumblyController < BenchController
    helper Crumbly::ViewHelpers, CrumblyRendering
  end
end

module Storefront
  class CrumblyController < BenchController
    helper Crumbly::ViewHelpers
  end
end

def view_for(controller_class)
  controller = controller_class.new
  controller.request = ActionDispatch::Request.new(Rack::MockRequest.env_for("https://example.com/customers/7/orders/42"))
  controller.view_context
end

gretel_view = view_for(GretelController)
admin_view = view_for(Admin::CrumblyController)
storefront_view = view_for(Storefront::CrumblyController)

def render_with(view)
  lambda do
    view.breadcrumb(:order, ORDER)
    yield(view).to_s
  end
end

CASES_BY_OUTPUT = {
  "<ol>" => {
    "gretel" => render_with(gretel_view) { |view| view.breadcrumbs(style: :ol) },
    "crumbly" => render_with(admin_view, &:crumbly_breadcrumbs)
  },
  "JSON-LD" => {
    "gretel" => render_with(gretel_view, &:gretel_json_ld),
    "crumbly" => render_with(storefront_view, &:breadcrumb_json_ld)
  }
}

puts "Ruby #{RUBY_VERSION}, YJIT #{(defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?) ? "on" : "off"}, " \
     "Rails #{Rails.version}, gretel #{Gretel::VERSION}, crumbly #{Crumbly::VERSION}"

ALLOCATION_RUNS = 1_000
CASES_BY_OUTPUT.each do |output, cases|
  puts
  cases.each do |name, render|
    puts "#{name} #{output}: #{render.call}"
    GC.disable
    before = GC.stat(:total_allocated_objects)
    ALLOCATION_RUNS.times { render.call }
    allocations = (GC.stat(:total_allocated_objects) - before) / ALLOCATION_RUNS
    GC.enable
    puts "#{name} #{output}: #{allocations} allocations per render"
  end

  Benchmark.ips do |benchmark|
    benchmark.config(warmup: 2, time: 5)
    cases.each { |name, render| benchmark.report("#{name} #{output}", &render) }
    benchmark.compare!
  end
end
