# frozen_string_literal: true

require "prism"

module GretelX
  class Verifier
    BREADCRUMB_CALL = /\bbreadcrumb[\s(]+(?::(\w+)|["'](\w+)["']|@(\w+))/
    ROUTE_HELPER = /_(?:path|url)\z/

    def initialize(trail_classes:, routes:, sources:)
      @trail_classes = trail_classes
      @routes = routes
      @sources = sources
      @problems = []
      @called_names = Set[:root]
      @definitions_by_path = {}
    end

    def call
      trail_classes.each { |trail_class| verify_crumbs(trail_class) }
      verify_sources
      raise InvalidTrail, "#{problems.size} breadcrumb problem(s):\n- #{problems.join("\n- ")}" if problems.any?

      dead_crumbs
    end

    private

    attr_reader :trail_classes, :routes, :sources, :problems, :called_names, :definitions_by_path

    def verify_crumbs(trail_class)
      crumb_methods = crumb_names(trail_class).map { |name| trail_class.instance_method(name) }
      crumb_paths = crumb_methods.filter_map { |crumb_method| crumb_method.source_location&.first }
      helper_methods = trail_class.private_instance_methods(false).map { |name| trail_class.instance_method(name) }
      helper_methods.select! { |helper_method| crumb_paths.include?(helper_method.source_location&.first) }

      (crumb_methods + helper_methods).each { |method| verify_calls(trail_class, method) }
    end

    def verify_calls(trail_class, method)
      definition = definition_of(method)
      return unless definition

      receiverless_calls(definition).each do |name, line|
        next if name == method.name

        called_names << name
        next if trail_class.method_defined?(name) || trail_class.private_method_defined?(name)

        kind = ROUTE_HELPER.match?(name) ? "a route helper" : "a crumb"
        problems << "#{trail_class}##{method.name} calls #{name}, which is not #{kind} " \
                    "(#{method.source_location.first}:#{line})"
      end
    end

    def definition_of(method)
      path, line = method.source_location
      return unless path && File.file?(path)

      definitions_by_path[path] ||= definitions_in(Prism.parse_file(path).value)
      definitions_by_path[path][[method.name, line]]
    end

    def definitions_in(tree)
      definitions = {}
      each_node(tree) do |node|
        definitions[[node.name, node.location.start_line]] = node if node.is_a?(Prism::DefNode)
      end
      definitions
    end

    def receiverless_calls(definition)
      calls = []
      each_node(definition) do |node|
        calls << [node.name, node.location.start_line] if node.is_a?(Prism::CallNode) && node.receiver.nil?
      end
      calls
    end

    def each_node(node, &block)
      yield node
      node.compact_child_nodes.each { |child| each_node(child, &block) }
    end

    def verify_sources
      defined_names = trail_classes.flat_map { |trail_class| crumb_names(trail_class) }.to_set
      source_files.each do |path|
        File.foreach(path).with_index(1) do |line, number|
          line.scan(BREADCRUMB_CALL) do |symbol, string, instance_variable|
            name = (symbol || string || instance_variable).to_sym
            called_names << name
            next if instance_variable || defined_names.include?(name)

            problems << "#{path}:#{number} calls breadcrumb :#{name}, which no trail defines"
          end
        end
      end
    end

    def source_files
      sources.flat_map { |source| Dir.glob(File.join(source, "**", "*")) }.select { |path| File.file?(path) }
    end

    def dead_crumbs
      reachable_names = called_names + derived_names
      trail_classes.flat_map do |trail_class|
        dead_names = crumb_names(trail_class).reject do |name|
          reachable_names.include?(name) || model_name?(name)
        end
        dead_names.map { |name| "#{trail_class}##{name}" }
      end
    end

    # The crumbs a derived trail reads: the collection and the record of each routed controller, and under a
    # nested route the collection named after its nesting (order_messages for /orders/:order_id/messages).
    def derived_names
      return [] unless routes

      routes.routes.flat_map { |route| derived_names_for(route) }.uniq
    end

    def derived_names_for(route)
      controller_name = route.defaults[:controller]&.split("/")&.last
      return [] unless controller_name

      parent_names = route.required_parts.filter_map { |part| part.to_s.delete_suffix("_id") if part.end_with?("_id") }
      nesting_names = (0..parent_names.size).map { |count| [*parent_names.first(count), controller_name].join("_").to_sym }
      [*nesting_names, controller_name.singularize.to_sym]
    end

    # A crumb named after a model is reachable from any `breadcrumb @record` or `crumb_for(record)`.
    def model_name?(name)
      name.to_s.camelize.safe_constantize.respond_to?(:model_name)
    end

    def crumb_names(trail_class)
      trail_class.own_crumb_names.select { |name| trail_class.public_method_defined?(name, false) }
    end
  end
end
