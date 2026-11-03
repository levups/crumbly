# frozen_string_literal: true

module GretelX
  module Controller
    extend ActiveSupport::Concern

    included do
      class_attribute :breadcrumbs_class, instance_accessor: false, default: nil
    end

    class_methods do
      def breadcrumbs_with(trail_class)
        self.breadcrumbs_class = trail_class
      end
    end
  end
end
