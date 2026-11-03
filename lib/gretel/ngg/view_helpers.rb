# frozen_string_literal: true

module Gretel
  module Ngg
    module ViewHelpers
      # The view names its crumb; a view that says nothing gets the trail derived from its controller and action.
      def breadcrumb(target, *arguments)
        @gretel_ngg_breadcrumb = [target, arguments]
        @gretel_ngg_trail = nil
      end

      def breadcrumb_trail
        @gretel_ngg_trail ||= begin
          trail_class = Ngg.trail_class_for(controller.class)
          if @gretel_ngg_breadcrumb
            target, arguments = @gretel_ngg_breadcrumb
            trail_class.resolve(self, target, *arguments)
          else
            trail_class.derive(self)
          end
        end
      end
    end
  end
end
