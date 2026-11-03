# frozen_string_literal: true

module Gretel
  module Ngg
    # One subclass per namespace (Admin::Breadcrumbs < Gretel::Ngg::Trail): each public method defined there is a crumb.
    class Trail
      # Included after the routes' url_helpers, whose own url_options would otherwise win.
      module UrlOptionsFromView
        def url_options
          helpers.url_options
        end
      end

      class << self
        attr_reader :own_crumb_names

        def inherited(subclass)
          super
          routes = Ngg.routes
          if routes
            subclass.include(routes.url_helpers)
            subclass.include(UrlOptionsFromView)
          end
          # Set last: including url_helpers defines methods in the subclass, which are not crumbs.
          subclass.instance_variable_set(:@own_crumb_names, Set.new)
        end

        def method_added(name)
          super
          return unless own_crumb_names && public_method_defined?(name, false)
          return if own_crumb_names.add?(name)

          raise DuplicateCrumb, "#{self}##{name} is defined twice: the second definition would replace the first"
        end

        def crumb?(name)
          trail_class = self
          while trail_class < Trail
            return trail_class.public_method_defined?(name) if trail_class.own_crumb_names.include?(name)

            trail_class = trail_class.superclass
          end
          false
        end

        def resolve(helpers, target, *arguments)
          new(helpers).send(:levels_for, target, arguments)
        end

        def derive(helpers)
          new(helpers).send(:derived_levels)
        end
      end

      def initialize(helpers)
        @helpers = helpers
      end

      private

      attr_reader :helpers

      def crumb(label, url = nil, parent: nil, links: [])
        Crumb.new(label:, url: path_for(url), links:, parent:)
      end

      def link(label, url)
        Link.new(label:, url: path_for(url))
      end

      # The crumb of a record, found by its model name: `parent: crumb_for(owner)` for a polymorphic parent.
      def crumb_for(record, *arguments)
        name = crumb_name_for(record)
        return public_send(name, record, *arguments) if name

        unknown_crumb("#{self.class} has no crumb for #{record.class}: define ##{record.model_name.singular}")
      end

      def path_for(url)
        case url
        when nil, String then url
        else polymorphic_path(url)
        end
      end

      def levels_for(target, arguments)
        levels(target_crumb(target, arguments))
      end

      def target_crumb(target, arguments)
        return crumb_for(target, *arguments) unless target.is_a?(Symbol) || target.is_a?(String)

        name = target.to_sym
        return public_send(name, *arguments) if self.class.crumb?(name)

        unknown_crumb("#{self.class} has no crumb named #{name}")
      end

      def levels(current_crumb)
        return [] unless current_crumb

        crumbs = []
        crumb = current_crumb
        while crumb
          crumbs << crumb
          crumb = crumb.parent
        end
        crumbs.reverse!
        if self.class.crumb?(:root)
          root_crumb = root
          crumbs.unshift(root_crumb) unless crumbs.first == root_crumb
        end

        last_index = crumbs.size - 1
        crumbs.each_with_index.map do |level_crumb, index|
          Level.new(label: level_crumb.label, url: level_crumb.url, links: level_crumb.links, current: index == last_index)
        end
      end

      # STI: a subclass without a crumb of its own falls back on its parent class's.
      def crumb_name_for(record)
        model_class = record.class
        loop do
          name = model_class.model_name.singular.to_sym
          return name if self.class.crumb?(name)
          return unless model_class.respond_to?(:base_class) && model_class != model_class.base_class

          model_class = model_class.superclass
        end
      end

      def unknown_crumb(message)
        exception = UnknownCrumb.new(message)
        raise exception if Ngg.raise_on_unknown_crumb?

        ActiveSupport.error_reporter.report(exception, handled: true)
        nil
      end

      def controller
        helpers.controller
      end

      def derived_levels
        levels(derived_crumb)
      end

      def derived_crumb
        record = controller.instance_variable_get(:"@#{controller.controller_name.singularize}")
        case controller.action_name
        when "index" then collection_crumb
        when "show" then record && record_crumb(record)
        when "new", "create" then new_record_crumb
        when "edit", "update" then record && edit_record_crumb(record)
        end
      end

      # The four crumbs below build a derived trail; override any of them as a private method.
      def collection_crumb
        name = controller.controller_name.to_sym
        return public_send(name) if self.class.crumb?(name)

        model_class = controller.controller_name.classify.safe_constantize
        label = name.to_s.humanize
        label = model_class.model_name.human(count: 2, default: label) if model_class.respond_to?(:model_name)
        crumb(label, route_path(action: "index"))
      end

      def record_crumb(record)
        return crumb_for(record) if crumb_name_for(record)

        crumb(record.to_s, route_path(action: "show", id: record), parent: collection_crumb)
      end

      def new_record_crumb
        crumb(I18n.t("gretel_ngg.new", default: "New"), parent: collection_crumb)
      end

      def edit_record_crumb(record)
        crumb(I18n.t("gretel_ngg.edit", default: "Edit"), parent: record_crumb(record))
      end

      # A controller without an index or show route still gets its level, without a link.
      def route_path(**options)
        helpers.url_for(controller: "/#{controller.controller_path}", only_path: true, **options)
      rescue ActionController::UrlGenerationError
        nil
      end
    end
  end
end
