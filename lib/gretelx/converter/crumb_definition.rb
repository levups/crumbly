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

      # A local assigned outside the crumbs. A lambda at the top of the file that reads no other local becomes a
      # private method of the Trail: `label.call(post)` reads `label(post)`. A proc keeps its lenient arity as a
      # copied local.
      Local = Data.define(:node, :source) do
        def helper_method?
          source.expansion_description.nil? && !function.nil? && (read_names(function.body) - scope_names).empty?
        end

        def method_lines
          parameters = function.parameters&.parameters&.slice
          body = function.body ? source.fragment(function.body, []).split("\n") : []
          [parameters ? "def #{node.name}(#{parameters})" : "def #{node.name}", *body.map { |line| "  #{line}" }, "end"]
        end

        private

        def function
          function = case node.value
          in Prism::LambdaNode => lambda then lambda
          in Prism::CallNode[receiver: nil, name: :lambda, block: Prism::BlockNode => block] then block
          else return nil
          end
          function unless function.parameters in Prism::NumberedParametersNode | Prism::ItParametersNode
        end

        def scope_names(node = function, names = [])
          names.concat(node.locals) if node in Prism::LambdaNode | Prism::BlockNode
          node&.compact_child_nodes&.each { |child| scope_names(child, names) }
          names
        end

        def read_names(node, names = [])
          names << node.name if node.is_a?(Prism::LocalVariableReadNode)
          node&.compact_child_nodes&.each { |child| read_names(child, names) }
          names
        end
      end

      attr_reader :key, :line, :notes

      def initialize(call, source, local_by_name: {})
        @call = call
        @source = source
        @local_by_name = local_by_name
        @line = call.location.start_line
        @notes = []
        @copied_ranges = []
        @key = crumb_key
        @block = call.block
        raise unconvertible("crumb :#{key} has no block") unless block.is_a?(Prism::BlockNode)
      end

      def lines
        body = copied_local_lines + body_lines(statements_of(block.body), [], nil)
        signature = parameters_source.empty? ? "def #{key}" : "def #{key}(#{parameters_source})"
        [*loose_comments, signature, *indent(body), "end"]
      end

      private

      attr_reader :call, :source, :block, :copied_ranges, :local_by_name

      # The locals assigned outside the block that it reads, and those they read, in the order of the file. A
      # literal is written in place instead (`path = :posts_path` makes `public_send(path)` read `posts_path`).
      def copied_local_lines
        names = read_names(block) - shadowed_names
        loop do
          more_names = names.flat_map { |name| read_names(local_by_name[name]&.node&.value) } - names
          more_names &= local_by_name.keys
          break if more_names.empty?

          names += more_names
        end
        copied_locals = local_by_name.slice(*local_by_name.keys.intersection(names)).values
        copied_locals.reject { |local| local.helper_method? || literal?(local.node.value) }.flat_map do |local|
          local.source.fragment(local.node, helper_edits(local.node)).split("\n")
        end
      end

      def helper_method_call(node)
        return unless node in Prism::CallNode[name: :call | :[], receiver: Prism::LocalVariableReadNode => receiver]
        return if shadowed_names.include?(receiver.name)

        receiver.name if local_by_name[receiver.name]&.helper_method?
      end

      def helper_method_edits(call, name, edits)
        arguments = call.arguments&.arguments || []
        if call.opening_loc
          edits << [call.location.start_offset, call.opening_loc.end_offset, "#{name}("]
          edits << [call.closing_loc.start_offset, call.closing_loc.end_offset, ")"]
        elsif arguments.empty?
          return edits << [call.location.start_offset, call.location.end_offset, name.to_s]
        else
          edits << [call.location.start_offset, arguments.first.location.start_offset, "#{name}("]
          edits << [call.location.end_offset, call.location.end_offset, ")"]
        end
        arguments.each { |argument| helper_edits(argument, edits) }
        edits
      end

      def literal?(node)
        Converter::STATIC_NODES.any? { |node_class| node.is_a?(node_class) }
      end

      def inlined_literal(node)
        return unless node.is_a?(Prism::LocalVariableReadNode) && !shadowed_names.include?(node.name)

        value = local_by_name[node.name]&.node&.value
        value if value && literal?(value)
      end

      # The names the crumb's block, and the blocks inside it, bind themselves: an outer local of that name is
      # not read there.
      def shadowed_names
        @shadowed_names ||= scope_locals(block).uniq
      end

      def scope_locals(node, names = [])
        names.concat(node.locals) if node in Prism::LambdaNode | Prism::BlockNode
        node.compact_child_nodes.each { |child| scope_locals(child, names) }
        names
      end

      def read_names(node, names = [])
        names << node.name if node.is_a?(Prism::LocalVariableReadNode) && !names.include?(node.name)
        node&.compact_child_nodes&.each { |child| read_names(child, names) }
        names
      end

      def crumb_key
        argument = call.arguments&.arguments&.first
        unless argument in Prism::SymbolNode | Prism::StringNode
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
        if parameters in Prism::NumberedParametersNode | Prism::ItParametersNode
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
        when Prism::IfNode, Prism::UnlessNode, Prism::CaseNode then tested_names(node.predicate, names)
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
      # call, ending the method or each branch of a conditional that calls them, the statements after the
      # conditional copied into each branch.
      def body_lines(statements, links, parent)
        lines = []
        statements.each_with_index do |statement, index|
          if crumb_dsl_call?(statement, :link)
            links += [statement]
          elsif crumb_dsl_call?(statement, :parent)
            parent = parent_target(statement)
          elsif (conditional_parent = conditional_parent_target(statement, parent))
            parent = conditional_parent
          elsif calls_crumb_dsl?(statement)
            unless conditional?(statement)
              raise unconvertible("crumb :#{key} calls link or parent inside #{summary(statement)}: left out, " \
                                  "convert it by hand", statement)
            end

            return lines + conditional_lines(statement, statements.drop(index + 1), links, parent)
          else
            lines.concat(fragment(statement).split("\n"))
          end
        end
        lines + result_lines(links, parent)
      end

      def conditional_lines(node, rest, links, parent)
        branch_lines = ->(statements) { body_lines(statements_of(statements) + rest, links, parent) }
        case node
        when Prism::UnlessNode
          predicate = fragment(node.predicate)
          negative_lines = branch_lines.call(node.statements)
          positive_lines = branch_lines.call(node.else_clause&.statements)
          return ["unless #{predicate}", *indent(negative_lines), "end"] if positive_lines.empty?

          ["if #{predicate}", *indent(positive_lines), "else", *indent(negative_lines), "end"]
        when Prism::CaseNode
          lines = [node.predicate ? "case #{fragment(node.predicate)}" : "case"]
          node.conditions.each do |condition|
            lines << "when #{condition.conditions.map { |value| fragment(value) }.join(", ")}"
            lines.concat(indent(branch_lines.call(condition.statements)))
          end
          else_lines = branch_lines.call(node.else_clause&.statements)
          lines.push("else", *indent(else_lines)) if else_lines.any?
          lines << "end"
        else
          lines = ["if #{fragment(node.predicate)}", *indent(branch_lines.call(node.statements))]
          subsequent = node.subsequent
          while subsequent.is_a?(Prism::IfNode)
            lines << "elsif #{fragment(subsequent.predicate)}"
            lines.concat(indent(branch_lines.call(subsequent.statements)))
            subsequent = subsequent.subsequent
          end
          else_lines = branch_lines.call(subsequent&.statements)
          lines.push("else", *indent(else_lines)) if else_lines.any?
          lines << "end"
        end
      end

      # `parent :a` in one branch and `parent :b` in the other: a single crumb whose parent is a ternary. A
      # branch without a parent keeps the one set before the conditional, as gretel does.
      def conditional_parent_target(node, previous_parent)
        return unless node in Prism::IfNode | Prism::UnlessNode

        else_node = node.is_a?(Prism::IfNode) ? node.subsequent : node.else_clause
        return if else_node.is_a?(Prism::IfNode)

        then_parent = single_parent_call(node.statements)
        else_parent = single_parent_call(else_node&.statements)
        return if then_parent.nil? || (else_node && else_parent.nil?)

        predicate = fragment(node.predicate)
        then_target = parent_target(then_parent)
        else_target = else_parent ? parent_target(else_parent) : previous_parent
        else_target = "(#{else_target})" if else_target&.include?(" ? ")
        # A modifier runs its predicate first but is read after its body: a local the predicate assigns
        # would be read as a method call.
        else_target ||= "nil" if writes_local?(node.predicate)
        condition = else_target && ternary_condition(node.predicate, predicate)
        if node.is_a?(Prism::IfNode)
          else_target ? "#{condition} ? #{then_target} : #{else_target}" : "(#{then_target} if #{predicate})"
        else
          else_target ? "#{condition} ? #{else_target} : #{then_target}" : "(#{then_target} unless #{predicate})"
        end
      end

      # `?:` binds tighter than `or`, `not` and `=`: `x or y ? a : b` would pass `x` as the parent.
      def ternary_condition(predicate, text)
        bare = (predicate in Prism::LocalVariableReadNode | Prism::InstanceVariableReadNode | Prism::ParenthesesNode |
          Prism::CallNode)
        bare &&= predicate.message != "not" if predicate.is_a?(Prism::CallNode)
        bare ? text : "(#{text})"
      end

      def writes_local?(node)
        return true if node in Prism::LocalVariableWriteNode | Prism::LocalVariableOperatorWriteNode |
          Prism::LocalVariableOrWriteNode | Prism::LocalVariableAndWriteNode | Prism::MultiWriteNode

        node.compact_child_nodes.any? { |child| writes_local?(child) }
      end

      def single_parent_call(statements)
        body = statements_of(statements)
        body.first if body.size == 1 && crumb_dsl_call?(body.first, :parent)
      end

      def parent_target(call)
        arguments = call.arguments&.arguments || []
        raise unconvertible("crumb :#{key} reads its parent instead of setting it: left out", call) if arguments.empty?

        target, *rest = arguments
        target = inlined_literal(target) || target
        rest = rest.map { |argument| fragment(argument) }
        case target
        in Prism::SymbolNode | Prism::StringNode
          name = target.unescaped.to_sym
          raise unconvertible("parent :#{name} cannot be a method of a Trail: rename it", call) unless method_name?(name)

          crumb_method_call(name, rest)
        in Prism::InterpolatedSymbolNode | Prism::CallNode[name: :to_sym]
          "public_send(#{[fragment(target), *rest].join(", ")})"
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
            arguments.any? { |argument| argument in Prism::SplatNode | Prism::KeywordHashNode }
          raise unconvertible("crumb :#{key} calls #{summary(link)}: left out, convert it by hand", link)
        end

        label, url = arguments
        [fragment(label), (url unless url.is_a?(Prism::NilNode)) && fragment(url)]
      end

      def crumb_dsl_call?(node, name)
        node in Prism::CallNode[receiver: nil, name: ^name, block: nil]
      end

      def calls_crumb_dsl?(node)
        return true if node in Prism::CallNode[receiver: nil, name: :link | :parent]

        node.compact_child_nodes.any? { |child| calls_crumb_dsl?(child) }
      end

      def conditional?(node)
        node in Prism::IfNode | Prism::UnlessNode | Prism::CaseNode
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
        if (literal = inlined_literal(node))
          return edits << [node.location.start_offset, node.location.end_offset, literal.slice]
        end
        if (helper_method = helper_method_call(node))
          return helper_method_edits(node, helper_method, edits)
        end
        if node.is_a?(Prism::LocalVariableReadNode) && !shadowed_names.include?(node.name) &&
            local_by_name[node.name]&.helper_method?
          return edits << [node.location.start_offset, node.location.end_offset, "method(:#{node.name})"]
        end
        if (method_name = static_send_name(node))
          arguments = node.arguments.arguments.drop(1)
          return edits << [node.location.start_offset, node.location.end_offset, method_name] if arguments.empty?

          edits << [node.location.start_offset, arguments.first.location.start_offset, "#{method_name}("]
          edits << [node.location.end_offset, node.location.end_offset, ")"] unless node.opening_loc
          arguments.each { |argument| helper_edits(argument, edits) }
          return edits
        end
        if node.is_a?(Prism::CallNode) && view_helper_call?(node)
          edits << [node.location.start_offset, node.location.start_offset, "helpers."]
        end
        node.compact_child_nodes.each { |child| helper_edits(child, edits) }
        edits
      end

      # `send("admin_#{name}_path", post)` in a loop reads `admin_posts_path(post)` once the loop is expanded.
      def static_send_name(node)
        return unless node in Prism::CallNode[receiver: nil, name: :send | :public_send, block: nil,
          arguments: {arguments: [target, *]}]

        target = inlined_literal(target) || target
        return unless target in Prism::StringNode | Prism::SymbolNode

        name = target.unescaped
        name if name.end_with?("_path", "_url") && name.match?(/\A[a-z_][a-z0-9_]*\z/)
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
