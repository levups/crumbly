# frozen_string_literal: true

require "test_helper"
require "open3"
require "tmpdir"

class ExecutableTest < ActiveSupport::TestCase
  EXECUTABLE = File.expand_path("../exe/gretelx-convert", __dir__)

  test "writes the class and prints what it left out" do
    Dir.mktmpdir do |directory|
      File.write("#{directory}/breadcrumbs.rb", <<~GRETEL)
        crumb :orders do
          link "Orders", admin_orders_path
        end

        ADMIN_SECTIONS.each do |section|
          crumb section do
            link section.to_s
          end
        end
      GRETEL

      output, errors, status = Open3.capture3(RbConfig.ruby, "-Ilib", EXECUTABLE, "#{directory}/breadcrumbs.rb",
        "--namespace", "Admin", "--output", "#{directory}/admin_breadcrumbs.rb")

      assert_predicate status, :success?
      assert_empty output
      assert_includes File.read("#{directory}/admin_breadcrumbs.rb"),
        "module Admin\n  class Breadcrumbs < GretelX::Trail\n    def orders\n"
      assert_equal "Not converted, or converted with a loss:\n  #{directory}/breadcrumbs.rb:5: crumbs defined in a " \
                   "loop over ADMIN_SECTIONS, which is not a literal: left out, write them by hand\n", errors
    end
  end

  test "an invalid namespace stops with a message" do
    _, errors, status = Open3.capture3(RbConfig.ruby, "-Ilib", EXECUTABLE, __FILE__, "--namespace", "admin")

    refute_predicate status, :success?
    assert_equal "gretelx-convert: \"admin\" is not a module name\n", errors
  end
end
