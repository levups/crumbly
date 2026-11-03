# frozen_string_literal: true

require "test_helper"
require "tmpdir"
require "gretelx/derived_call_sites"

class DerivedCallSitesTest < ActiveSupport::TestCase
  VIEWS = {
    "orders/index.html.erb" => "<% breadcrumb :orders %>\n",
    "orders/show.html.slim" => "- breadcrumb @order\n",
    "orders/new.html.erb" => "<h1>New order</h1>\n<% breadcrumb :generic_form, @order %>\n",
    "orders/edit.html.haml" => "- breadcrumb(:generic_form, @order)\n",
    "orders/_form.html.erb" => "<% breadcrumb :generic_form, order %>\n",
    "orders/messages.html.erb" => "<% breadcrumb :order_messages, @order %>\n",
    "customers/show.html.erb" => "<% breadcrumb :customer, @customer %>\n",
    "customers/index.html.erb" => "<% breadcrumb :customers, scope: :active %>\n"
  }.freeze

  test "lists the calls that the action's derived trail may cover, and leaves the files as they are" do
    Dir.mktmpdir do |directory|
      VIEWS.each do |path, content|
        FileUtils.mkdir_p(File.dirname("#{directory}/#{path}"))
        File.write("#{directory}/#{path}", content)
      end

      call_sites = GretelX::DerivedCallSites.call(directory).map { |call_site| call_site.to_s.delete_prefix("#{directory}/") }

      assert_equal [
        "customers/show.html.erb:1: breadcrumb :customer, @customer (show derives the crumb of @customer)",
        "orders/_form.html.erb:1: breadcrumb :generic_form, order (only new and edit views derive a form's trail)",
        "orders/edit.html.haml:1: breadcrumb(:generic_form, @order) (edit derives « Edit » under the record)",
        "orders/index.html.erb:1: breadcrumb :orders (index derives the orders crumb)",
        "orders/new.html.erb:2: breadcrumb :generic_form, @order (new derives « New » under the collection)",
        "orders/show.html.slim:1: breadcrumb @order (show derives the crumb of @order)"
      ], call_sites
      VIEWS.each { |path, content| assert_equal content, File.read("#{directory}/#{path}") }
    end
  end
end
