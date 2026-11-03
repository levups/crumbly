# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/class/attribute"
require "active_support/core_ext/module/introspection"
require "active_support/core_ext/string/inflections"
require "i18n"

require_relative "ngg/version"
require_relative "ngg/errors"
require_relative "ngg/crumb"
require_relative "ngg/level"
require_relative "ngg/trail"
require_relative "ngg/json_ld"
require_relative "ngg/controller"
require_relative "ngg/view_helpers"
require_relative "ngg/railtie" if defined?(Rails::Railtie)

module Gretel
  module Ngg
    class << self
      attr_writer :routes, :raise_on_unknown_crumb, :raise_on_relative_url

      def routes
        @routes || (Rails.application&.routes if defined?(Rails.application))
      end

      def raise_on_unknown_crumb?
        return @raise_on_unknown_crumb unless @raise_on_unknown_crumb.nil?

        !production?
      end

      def raise_on_relative_url?
        return @raise_on_relative_url unless @raise_on_relative_url.nil?

        !production?
      end

      # Admin::OrdersController reads Admin::Breadcrumbs, then ::Breadcrumbs, unless it calls breadcrumbs_with.
      def trail_class_for(controller_class)
        explicit_trail_class = controller_class.try(:breadcrumbs_class)
        return explicit_trail_class if explicit_trail_class

        namespace = controller_class.module_parent
        loop do
          trail_class = namespace.const_get(:Breadcrumbs, false) if namespace.const_defined?(:Breadcrumbs, false)
          return trail_class if trail_class.is_a?(Class) && trail_class < Trail
          break if namespace == Object

          namespace = namespace.module_parent
        end
        namespace = controller_class.module_parent
        trail_class_name = (namespace == Object) ? "Breadcrumbs" : "#{namespace}::Breadcrumbs"
        raise MissingTrail, "#{controller_class} has no breadcrumbs: define #{trail_class_name} " \
                            "(a Gretel::Ngg::Trail) or call breadcrumbs_with in the controller"
      end

      private

      def production?
        defined?(Rails.env) && Rails.env.production?
      end
    end
  end
end
