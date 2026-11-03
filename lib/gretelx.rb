# frozen_string_literal: true

require "active_support"
require "active_support/core_ext/class/attribute"
require "active_support/core_ext/class/subclasses"
require "active_support/core_ext/module/introspection"
require "active_support/core_ext/string/inflections"
require "i18n"

require_relative "gretelx/version"
require_relative "gretelx/errors"
require_relative "gretelx/crumb"
require_relative "gretelx/level"
require_relative "gretelx/trail"
require_relative "gretelx/json_ld"
require_relative "gretelx/controller"
require_relative "gretelx/view_helpers"
require_relative "gretelx/verifier"
require_relative "gretelx/railtie" if defined?(Rails::Railtie)

module GretelX
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

    # Raises InvalidTrail with every problem found, and returns the dead crumbs ("Admin::Breadcrumbs#drafts").
    def verify!(trail_classes: nil, routes: GretelX.routes, sources: default_sources)
      Rails.application.eager_load! if trail_classes.nil? && defined?(Rails.application) && Rails.application
      Verifier.new(trail_classes: trail_classes || Trail.descendants, routes:, sources:).call
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
                          "(a GretelX::Trail) or call breadcrumbs_with in the controller"
    end

    private

    def default_sources
      return [] unless defined?(Rails.root) && Rails.root

      [Rails.root.join("app/views"), Rails.root.join("app/controllers")]
    end

    def production?
      defined?(Rails.env) && Rails.env.production?
    end
  end
end
