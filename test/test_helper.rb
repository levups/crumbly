# frozen_string_literal: true

require "minitest/autorun"
require "action_controller"
require "action_dispatch/testing/integration"
require "active_model"
require "gretel/ngg"

ROUTES = ActionDispatch::Routing::RouteSet.new
ROUTES.draw do
  namespace :admin do
    root "home#show"
    resources :orders do
      resources :messages, only: :index
      resources :returns, only: :index
    end
    resources :customers, only: :show do
      resources :returns, only: :index
    end
    resources :returns, only: :index
    resources :categories
    resources :posts
    get "reports/sales", to: "reports#sales", as: :sales_report
  end

  namespace :storefront do
    root "home#show"
    resources :categories, only: :show
    get "search", to: "search#show"
  end
end

Gretel::Ngg.routes = ROUTES
ActionController::Base.include(Gretel::Ngg::Controller)
ActionView::Base.include(Gretel::Ngg::ViewHelpers)

class ApplicationController < ActionController::Base
  include ROUTES.url_helpers
end

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

class Category < Record
  attr_accessor :name, :parent

  # One query in a real app: the whole chain, root first.
  def ancestors
    parent ? [*parent.ancestors, parent] : []
  end

  def to_s
    name
  end
end

class Post < Record
  attr_accessor :title

  def to_s
    title
  end
end

ALICE = Customer.new(id: 7, name: "Alice")
ORDER = Order.new(id: 42, number: "2026-0042", customer: ALICE)
AUDIO = Category.new(id: 1, name: "Audio")
SPEAKERS = Category.new(id: 2, name: "Speakers", parent: AUDIO)
BOOKSHELF = Category.new(id: 3, name: "Bookshelf speakers", parent: SPEAKERS)
POST = Post.new(id: 5, title: "Hello")

module Admin
  class Breadcrumbs < Gretel::Ngg::Trail
    def root
      crumb "Home", admin_root_path
    end

    def orders
      crumb "Orders", admin_orders_path
    end

    def order(order)
      crumb order.to_s, admin_order_path(order), parent: orders,
        links: [link("Invoice", "/admin/orders/#{order.id}/invoice.pdf")]
    end

    def order_messages(order)
      crumb "Messages", admin_order_messages_path(order), parent: order(order)
    end

    def customer(customer)
      crumb customer.to_s, [:admin, customer]
    end

    def returns(owner = nil)
      return crumb("Returns", admin_returns_path) unless owner

      crumb "Returns", [:admin, owner, :returns], parent: crumb_for(owner)
    end

    def categories
      crumb "Categories", admin_categories_path
    end

    def category(category, ancestors = category.ancestors)
      *grandparents, parent_category = ancestors
      crumb category.name, admin_category_path(category),
        parent: parent_category ? category(parent_category, grandparents) : categories
    end

    def sales_report
      crumb "Sales"
    end
  end

  class OrdersController < ApplicationController
    TRAIL = <<~ERB
      <%== breadcrumb_trail.map { |level| [level.label, level.url, (level.current? ? "current" : nil), *level.links.map(&:label)].compact.join("|") }.join(" > ") %>
    ERB

    def index
      render inline: TRAIL
    end

    def show
      @order = ORDER
      render inline: TRAIL
    end
  end

  class MessagesController < ApplicationController
    def index
      @order = ORDER
      render inline: "<% breadcrumb :order_messages, @order %>#{OrdersController::TRAIL}"
    end
  end

  class ReturnsController < ApplicationController
    def index
      owner = ORDER if params[:order_id]
      owner = ALICE if params[:customer_id]
      render inline: "<% breadcrumb :returns, owner %>#{OrdersController::TRAIL}", locals: {owner:}
    end
  end

  class CategoriesController < ApplicationController
    def show
      @category = BOOKSHELF
      render inline: "<% breadcrumb @category %>#{OrdersController::TRAIL}"
    end
  end

  class PostsController < ApplicationController
    def index
      render inline: OrdersController::TRAIL
    end

    def show
      @post = POST
      render inline: OrdersController::TRAIL
    end

    def new
      @post = Post.new
      render inline: OrdersController::TRAIL
    end

    def edit
      @post = POST
      render inline: OrdersController::TRAIL
    end
  end

  class ReportsController < ApplicationController
    def sales
      render inline: "<% breadcrumb :sales_report %>#{OrdersController::TRAIL}"
    end
  end
end

module Storefront
  class Breadcrumbs < Gretel::Ngg::Trail
    def categories
      crumb "Shop", storefront_root_url
    end

    def category(category)
      crumb category.name, storefront_category_url(category),
        parent: category.parent ? category(category.parent) : categories
    end

    def search(query)
      crumb "Search: #{query}", storefront_search_url(q: query), parent: categories
    end
  end

  class SearchController < ApplicationController
    def show
      render inline: "<% breadcrumb :search, params[:q] %><%= breadcrumb_json_ld %>"
    end
  end

  class CategoriesController < ApplicationController
    def show
      render inline: "<% breadcrumb SPEAKERS %>#{Admin::OrdersController::TRAIL}"
    end
  end
end

class IntegrationTestCase < ActionDispatch::IntegrationTest
  def app
    ROUTES
  end

  def assert_trail(expected, path)
    get path
    assert_response :success
    assert_equal expected, response.body.strip
  end
end
