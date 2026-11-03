# frozen_string_literal: true

module GretelX
  class Converter
    # One gretel `crumb :key do |arguments| ... end`, written as the `def key(arguments)` of a Trail.
    class CrumbDefinition
      KEYWORDS = %i[
        BEGIN END __ENCODING__ __FILE__ __LINE__ alias and begin break case class def defined? do else elsif end
        ensure false for if in module next nil not or redo rescue retry return self super then true undef unless
        until when while yield
      ].freeze
      TRAIL_METHODS = %i[controller polymorphic_path polymorphic_url url_for url_options].freeze
      NIL_TOLERANT_CALLS = %i[! nil? present? blank? presence].freeze
      SINGLE_LINE_LENGTH = 90

      attr_reader :key, :line, :notes

      def initialize(call, source)
        @call = call
        @source = source
        @line = call.location.start_line
        @notes = []
        @copied_ranges = []
        @key = crumb_key
        @block = call.block
        raise unconvertible("crumb :#{key} has no block") unless block.is_a?(Prism::BlockNode)
      end

      def lines
        body = body_lines(statements_of(block.body), [], nil)
        signature = parameters_source.empty? ? "def #{key}" : "def #{key}(#{parameters_source})"
        [*loose_comments, signature, *indent(body), "end"]
      end

      private

      attr_reader :call, :source, :block, :copied_ranges

      def crumb_key
        argument = call.arguments&.arguments&.first
        unless argument.is_a?(Prism::SymbolNode) || argument.is_a?(Prism::StringNode)
          raise unconvertible("crumb key #{argument&.slice.inspect} is not a literal symbol: left out")
        end

        name = argument.unescaped.to_sym
        raise unconvertible("crumb :#{name} cannot be a method of a Trail: rename it") unless method_name?(name)

        name
      end

      def method_name?(name)
        name.match?(/\A[a-z_][a-zA-Z0-9_]*[?!]?\z/) && !KEYWORDS.include?(name) &&
          !Object.method_defined?(name) && !Trail.private_method_defined?(name)
      end

      def parameters_source
        @parameters_source ||= block_parameters_source
      end

      # gretel runs a crumb as a block, which accepts fewer arguments than it declares: a parameter the
      # crumb tests for nil gets a nil default, and so do the ones after it.
      def block_parameters_source
        parameters = block.parameters
        if parameters.is_a?(Prism::NumberedParametersNode) || parameters.is_a?(Prism::ItParametersNode)
          raise unconvertible("crumb :#{key} uses numbered parameters: left out")
        end

        parameters = parameters&.parameters
        return "" unless parameters

        nil_tested = nil_tested_names(block.body)
        defaulted = false
        requireds = parameters.requireds.map do |parameter|
          defaulted ||= parameter.is_a?(Prism::RequiredParameterNode) && nil_tested.include?(parameter.name)
          defaulted ? "#{parameter.name} = nil" : fragment(parameter)
        end
        others = [*parameters.optionals, parameters.rest, *parameters.posts, *parameters.keywords,
          parameters.keyword_rest, parameters.block]
        others = others.filter_map do |parameter|
          fragment(parameter) unless parameter.nil? || parameter.is_a?(Prism::ImplicitRestNode)
        end
        [*requireds, *others].join(", ")
      end

      def nil_tested_names(node, names = Set.new)
        case node
        when Prism::IfNode, Prism::UnlessNode then tested_names(node.predicate, names)
        when Prism::CallNode
          names << node.receiver.name if node.safe_navigation? && node.receiver.is_a?(Prism::LocalVariableReadNode)
        end
        node&.compact_child_nodes&.each { |child| nil_tested_names(child, names) }
        names
      end

      def tested_names(predicate, names)
        case predicate
        when Prism::LocalVariableReadNode then names << predicate.name
        when Prism::CallNode
          tested_names(predicate.receiver, names) if NIL_TOLERANT_CALLS.include?(predicate.name)
        when Prism::AndNode, Prism::OrNode
          tested_names(predicate.left, names)
          tested_names(predicate.right, names)
        when Prism::ParenthesesNode
          predicate.body&.compact_child_nodes&.each { |child| tested_names(child, names) }
        end
      end

      # gretel adds a level per `link` and keeps the last `parent`, in any order: they become one `crumb`
      # call, ending the method or each branch of the conditional that ends it.
      def body_lines(statements, links, parent)
        lines = []
        statements.each_with_index do |statement, index|
          if crumb_dsl_call?(statement, :link)
            links += [statement]
          elsif crumb_dsl_call?(statement, :parent)
            parent = parent_target(statement)
          elsif (conditional_parent = conditional_parent_target(statement))
            parent = conditional_parent
          elsif calls_crumb_dsl?(statement)
            unless conditional?(statement) && index == statements.size - 1
              raise unconvertible("crumb :#{key} calls link or parent inside #{summary(statement)}: left out, " \
                                  "convert it by hand", statement)
            end

            return lines + conditional_lines(statement, links, parent)
          else
            lines.concat(fragment(statement).split("\n"))
          end
        end
        lines + result_lines(links, parent)
      end

      def conditional_lines(node, links, parent)
        predicate = fragment(node.predicate)
        if node.is_a?(Prism::UnlessNode)
          negative_lines = body_lines(statements_of(node.statements), links, parent)
          positive_lines = body_lines(statements_of(node.else_clause&.statements), links, parent)
          return ["unless #{predicate}", *indent(negative_lines), "end"] if positive_lines.empty?

          return ["if #{predicate}", *indent(positive_lines), "else", *indent(negative_lines), "end"]
        end

        lines = ["if #{predicate}", *indent(body_lines(statements_of(node.statements), links, parent))]
        subsequent = node.subsequent
        while subsequent.is_a?(Prism::IfNode)
          lines << "elsif #{fragment(subsequent.predicate)}"
          lines.concat(indent(body_lines(statements_of(subsequent.statements), links, parent)))
          subsequent = subsequent.subsequent
        end
        else_lines = body_lines(statements_of(subsequent&.statements), links, parent)
        lines.push("else", *indent(else_lines)) if else_lines.any?
        lines << "end"
      end

      # `parent :a` in one branch and `parent :b` in the other: a single crumb whose parent is a ternary.
      def conditional_parent_target(node)
        return unless conditional?(node)

        else_node = node.is_a?(Prism::IfNode) ? node.subsequent : node.else_clause
        return if else_node.is_a?(Prism::IfNode)

        then_parent = single_parent_call(node.statements)
        else_parent = single_parent_call(else_node&.statements)
        return if then_parent.nil? || (else_node && else_parent.nil?)

        predicate = fragment(node.predicate)
        then_target = parent_target(then_parent)
        else_target = else_parent && parent_target(else_parent)
        if node.is_a?(Prism::IfNode)
          else_target ? "#{predicate} ? #{then_target} : #{else_target}" : "(#{then_target} if #{predicate})"
        else
          else_target ? "#{predicate} ? #{else_target} : #{then_target}" : "(#{then_target} unless #{predicate})"
        end
      end

      def single_parent_call(statements)
        body = statements_of(statements)
        body.first if body.size == 1 && crumb_dsl_call?(body.first, :parent)
      end

      def parent_target(call)
        arguments = call.arguments&.arguments || []
        raise unconvertible("crumb :#{key} reads its parent instead of setting it: left out", call) if arguments.empty?

        target, *rest = arguments
        rest = rest.map { |argument| fragment(argument) }
        case target
        when Prism::SymbolNode, Prism::StringNode
          name = target.unescaped.to_sym
          raise unconvertible("parent :#{name} cannot be a method of a Trail: rename it", call) unless method_name?(name)

          crumb_method_call(name, rest)
        when Prism::InterpolatedSymbolNode then "public_send(#{[fragment(target), *rest].join(", ")})"
        when Prism::CallNode
          return "public_send(#{[fragment(target), *rest].join(", ")})" if target.name == :to_sym

          "crumb_for(#{[fragment(target), *rest].join(", ")})"
        else
          "crumb_for(#{[fragment(target), *rest].join(", ")})"
        end
      end

      def crumb_method_call(name, arguments)
        return "#{name}(#{arguments.join(", ")})" if arguments.any?

        block.locals.include?(name) ? "self.#{name}" : name.to_s
      end

      def result_lines(links, parent)
        return parent ? parent.split("\n") : [] if links.empty?

        (label, url), *other_links = links.map { |link| link_sources(link) }
        arguments = [label, url].compact
        keywords = []
        keywords << "parent: #{parent}" if parent
        if other_links.any?
          keywords << "links: [#{other_links.map { |link_label, link_url| "link(#{link_label}, #{link_url || "nil"})" }.join(", ")}]"
        end

        single_line = "crumb #{[*arguments, *keywords].join(", ")}"
        return single_line.split("\n") if single_line.length <= SINGLE_LINE_LENGTH || keywords.empty?

        ["crumb #{arguments.join(", ")},", *keywords.map { |keyword| "  #{keyword}" }.join(",\n").split("\n")]
      end

      def link_sources(link)
        arguments = link.arguments&.arguments.to_a.dup
        if arguments.size > 1 && arguments.last.is_a?(Prism::KeywordHashNode)
          options = arguments.pop
          notes << "crumb :#{key}: link options #{options.slice} have no equivalent in GretelX: left out"
        end
        if arguments.empty? || arguments.size > 2 || link.block ||
            arguments.any? { |argument| argument.is_a?(Prism::SplatNode) || argument.is_a?(Prism::KeywordHashNode) }
          raise unconvertible("crumb :#{key} calls #{summary(link)}: left out, convert it by hand", link)
        end

        label, url = arguments
        [fragment(label), (url unless url.is_a?(Prism::NilNode)) && fragment(url)]
      end

      def crumb_dsl_call?(node, name)
        node.is_a?(Prism::CallNode) && node.receiver.nil? && node.name == name && node.block.nil?
      end

      def calls_crumb_dsl?(node)
        return true if node.is_a?(Prism::CallNode) && node.receiver.nil? && %i[link parent].include?(node.name)

        node.compact_child_nodes.any? { |child| calls_crumb_dsl?(child) }
      end

      def conditional?(node)
        node.is_a?(Prism::IfNode) || node.is_a?(Prism::UnlessNode)
      end

      def statements_of(node)
        case node
        when nil then []
        when Prism::StatementsNode then node.body
        else raise unconvertible("crumb :#{key} uses begin, rescue or ensure: left out, convert it by hand", node)
        end
      end

      # A gretel crumb reaches the view through method_missing; a Trail reaches it through `helpers`.
      def fragment(node)
        copied_ranges << (node.location.start_offset...node.location.end_offset)
        source.fragment(node, helper_edits(node))
      end

      def helper_edits(node, edits = [])
        if (method_name = static_send_name(node))
          return edits << [node.location.start_offset, node.location.end_offset, method_name]
        end
        if node.is_a?(Prism::CallNode) && view_helper_call?(node)
          edits << [node.location.start_offset, node.location.start_offset, "helpers."]
        end
        node.compact_child_nodes.each { |child| helper_edits(child, edits) }
        edits
      end

      # `send("admin_#{name}_path")` in a loop reads `admin_posts_path` once the loop is expanded.
      def static_send_name(node)
        return unless node.is_a?(Prism::CallNode) && node.receiver.nil? && %i[send public_send].include?(node.name)

        arguments = node.arguments&.arguments
        name = arguments.first if arguments&.size == 1 && node.block.nil?
        return unless name.is_a?(Prism::StringNode) || name.is_a?(Prism::SymbolNode)

        name.unescaped if name.unescaped.end_with?("_path", "_url") && name.unescaped.match?(/\A[a-z_][a-z0-9_]*\z/)
      end

      def view_helper_call?(call)
        name = call.name
        call.receiver.nil? && !%i[link parent].include?(name) && !name.end_with?("_path", "_url") &&
          !TRAIL_METHODS.include?(name) && !Kernel.method_defined?(name) && !Kernel.private_method_defined?(name)
      end

      def loose_comments
        source.comments.filter_map do |comment|
          offset = comment.location.start_offset
          next unless offset.between?(block.location.start_offset, block.location.end_offset)
          next if copied_ranges.any? { |range| range.cover?(offset) }

          comment.slice.rstrip
        end
      end

      def indent(lines)
        lines.map { |line| line.empty? ? line : "  #{line}" }
      end

      def summary(node)
        first_line = node.slice.lines.first.strip
        (first_line.length > 40) ? "#{first_line[0, 37]}..." : first_line
      end

      def unconvertible(message, node = call)
        Unconvertible.new(message, node.location.start_line)
      end
    end
  end
end
