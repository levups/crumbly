# frozen_string_literal: true

module GretelX
  # One subclass per namespace (Admin::Breadcrumbs < GretelX::Trail): each public method defined there is a crumb.
  class Trail
    RouteParent = Data.define(:name, :id, :record)

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
        routes = GretelX.routes
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
    def crumb_for(record, *)
      name = crumb_name_for(record)
      return public_send(name, record, *) if name

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
      return crumb_for(target, *arguments) unless target in Symbol | String

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
      raise exception if GretelX.raise_on_unknown_crumb?

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
      nested_collection_crumb(controller.controller_name, route_parents)
    end

    def record_crumb(record)
      return crumb_for(record) if crumb_name_for(record)

      crumb(record.to_s, route_path(action: "show", id: record), parent: collection_crumb)
    end

    def new_record_crumb
      crumb(I18n.t("gretelx.new", default: "New"), parent: collection_crumb)
    end

    def edit_record_crumb(record)
      crumb(I18n.t("gretelx.edit", default: "Edit"), parent: record_crumb(record))
    end

    # Under a nested route (/orders/42/messages), a crumb named after the whole nesting (order_messages) is
    # called with the parents' records; otherwise the collection is derived under its parent record.
    def nested_collection_crumb(name, parents)
      loaded_parents = parents.take_while(&:record)
      if loaded_parents.size < parents.size
        missing_parent = parents[loaded_parents.size]
        parent = nested_collection_crumb(missing_parent.name.pluralize, loaded_parents)
        return derived_collection_crumb(name, parents, parent:)
      end

      crumb_name = [*parents.map(&:name), name].join("_").to_sym
      return public_send(crumb_name, *parents.map(&:record)) if self.class.crumb?(crumb_name)

      derived_collection_crumb(name, parents, parent: parents.empty? ? nil : parent_record_crumb(parents))
    end

    def derived_collection_crumb(name, parents, parent:)
      model_class = name.classify.safe_constantize
      label = name.humanize
      label = model_class.model_name.human(count: 2, default: label) if model_class.respond_to?(:model_name)
      crumb(label, route_path(resources: name, action: "index", **route_parent_ids(parents)), parent:)
    end

    def parent_record_crumb(parents)
      *ancestors, parent = parents
      return crumb_for(parent.record) if crumb_name_for(parent.record)

      name = parent.name.pluralize
      crumb(parent.record.to_s, route_path(resources: name, action: "show", id: parent.id, **route_parent_ids(ancestors)),
        parent: nested_collection_crumb(name, ancestors))
    end

    # The record of each :<name>_id path parameter, outermost first, as the controller loaded it (@<name>).
    def route_parents
      controller.request.path_parameters.filter_map do |key, value|
        next unless key.end_with?("_id")

        name = key.to_s.delete_suffix("_id")
        RouteParent.new(name:, id: value, record: controller.instance_variable_get(:"@#{name}"))
      end
    end

    def route_parent_ids(parents)
      parents.to_h { |parent| [:"#{parent.name}_id", parent.id] }
    end

    # A controller without an index or show route still gets its level, without a link.
    def route_path(resources: controller.controller_name, **options)
      namespace = controller.controller_path.delete_suffix(controller.controller_name)
      helpers.url_for(controller: "/#{namespace}#{resources}", only_path: true, **options)
    rescue ActionController::UrlGenerationError
      nil
    end
  end
end
