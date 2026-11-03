# frozen_string_literal: true

require "gretelx"

module GretelX
  module TestHelper
    def assert_breadcrumbs_valid(**options)
      dead_crumbs = GretelX.verify!(**options)
      assert_empty dead_crumbs, "Dead crumbs, called by no crumb, view or controller: #{dead_crumbs.join(", ")}"
    rescue InvalidTrail => exception
      flunk exception.message
    end
  end
end

ActiveSupport.on_load(:active_support_test_case) { include GretelX::TestHelper }
