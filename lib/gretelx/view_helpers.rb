# frozen_string_literal: true

module GretelX
  module ViewHelpers
    # The view names its crumb; a view that says nothing gets the trail derived from its controller and action.
    def breadcrumb(target, *arguments)
      @gretelx_breadcrumb = [target, arguments]
      @gretelx_trail = nil
    end

    def breadcrumb_trail
      @gretelx_trail ||= begin
        trail_class = GretelX.trail_class_for(controller.class)
        if @gretelx_breadcrumb
          target, arguments = @gretelx_breadcrumb
          trail_class.resolve(self, target, *arguments)
        else
          trail_class.derive(self)
        end
      end
    end

    def breadcrumb_json_ld
      breadcrumb_list = JsonLd.call(breadcrumb_trail)
      return unless breadcrumb_list

      content_tag(:script, ERB::Util.json_escape(JSON.generate(breadcrumb_list)).html_safe, type: "application/ld+json")
    end
  end
end
