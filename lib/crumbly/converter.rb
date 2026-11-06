# frozen_string_literal: true

require "prism"
require "crumbly"
require_relative "converter/source"
require_relative "converter/crumb_definition"

if Gem::Version.new(Prism::VERSION) < Gem::Version.new("1.2")
  raise LoadError, "crumbly-convert needs prism 1.2 or later (#{Prism::VERSION} is loaded): add gem \"prism\" " \
                   "to your Gemfile"
end

module Crumbly
  # Turns gretel's breadcrumbs files into one Crumbly::Trail subclass, and lists what it leaves out.
  class Converter
    Result = Data.define(:ruby, :notes)

    Note = Data.define(:path, :line, :message) do
      def to_s
        "#{path}:#{line}: #{message}"
      end
    end

    class Unconvertible < StandardError
      attr_reader :line

      def initialize(message, line)
        super(message)
        @line = line
      end
    end

    Definition = Data.define(:key, :path, :line, :lines)

    STATIC_NODES = [
      Prism::SymbolNode, Prism::StringNode, Prism::IntegerNode, Prism::FloatNode,
      Prism::NilNode, Prism::TrueNode, Prism::FalseNode, Prism::ConstantReadNode, Prism::ConstantPathNode
    ].freeze
    LoopValue = Data.define(:source, :text)

    def self.call(source_by_path, namespace: nil)
      new(source_by_path, namespace:).call
    end

    def initialize(source_by_path, namespace:)
      unless namespace.nil? || namespace.match?(/\A[A-Z]\w*(::[A-Z]\w*)*\z/)
        raise ArgumentError, "#{namespace.inspect} is not a module name"
      end

      @source_by_path = source_by_path
      @namespace = namespace
      @entries = []
      @definition_by_key = {}
      @notes = []
      @helper_methods = []
    end

    def call
      source_by_path.each do |path, text|
        source = Source.parse(text, path:)
        convert_statements(source.statements, source)
        trailing_comments = source.comment_lines(source.statements.last&.location&.end_offset || 0, text.bytesize)
        entries << trailing_comments if trailing_comments.any?
      end
      Result.new(ruby: render, notes: notes.sort_by { |note| [note.path, note.line] })
    end

    private

    attr_reader :source_by_path, :namespace, :entries, :definition_by_key, :notes, :helper_methods

    # A crumb becomes a method, which cannot see the locals assigned around it: each one it reads is copied in.
    def convert_statements(statements, source, local_by_name = {})
      previous_end_offset = source.start_offset
      statements.each do |statement|
        comments = source.comment_lines(previous_end_offset, statement.location.start_offset)
        previous_end_offset = statement.location.end_offset
        convert_statement(statement, source, comments, local_by_name)
      rescue Unconvertible => exception
        note(source, exception.line, exception.message)
      end
    end

    def convert_statement(statement, source, comments, local_by_name)
      if crumb_call?(statement)
        define(CrumbDefinition.new(statement, source, local_by_name:), source, comments)
      elsif statement.is_a?(Prism::LocalVariableWriteNode)
        if local_by_name.key?(statement.name)
          note(source, statement.location.start_line, "#{statement.name} is assigned again: a crumb above that " \
                                                      "reads it gets its first value, where gretel read the last one")
        end
        local = CrumbDefinition::Local.new(node: statement, source:)
        helper_methods << comments + local.method_lines if local.helper_method?
        local_by_name[statement.name] = local
      elsif loop_call?(statement)
        entries << comments if comments.any?
        expand_loop(statement, source, local_by_name)
      else
        raise Unconvertible.new("not a crumb definition, left out: #{summary(statement)}",
          statement.location.start_line)
      end
    end

    def crumb_call?(node)
      node in Prism::CallNode[receiver: nil, name: :crumb]
    end

    def loop_call?(node)
      node in Prism::CallNode[name: :each | :each_pair, receiver: Prism::Node, block: Prism::BlockNode]
    end

    def define(crumb_definition, source, comments)
      key = crumb_definition.key
      lines = comments + crumb_definition.lines
      crumb_definition.notes.uniq.each { |message| note(source, crumb_definition.line, message) }
      line = crumb_definition.line

      if (previous = definition_by_key[key])
        entries.delete(previous)
        notes << Note.new(path: previous.path, line: previous.line,
          message: "crumb :#{key} is defined again on #{source.path}:#{line}, which gretel kept: left out")
      end
      definition = Definition.new(key:, path: source.path, line:, lines:)
      definition_by_key[key] = definition
      entries << definition
    end

    def expand_loop(call, source, local_by_name)
      block = call.block
      parameters = loop_parameters(block)
      unless parameters
        raise Unconvertible.new("crumbs defined in a loop whose block takes #{block.parameters&.slice.inspect}: " \
                                "left out, write them by hand", call.location.start_line)
      end

      bindings = literal_bindings(call.receiver, parameters, call.name)
      unless bindings
        raise Unconvertible.new("crumbs defined in a loop over #{summary(call.receiver)}, which is not a literal: " \
                                "left out, write them by hand", call.location.start_line)
      end

      start_offset = block.parameters ? block.parameters.location.end_offset : block.opening_loc.end_offset
      bindings.each do |value_by_name|
        text = source.rewrite(start_offset, block.closing_loc.start_offset, substitutions(block.body, value_by_name))
        expansion = value_by_name.map { |name, value| "#{name} = #{value.source}" }.join(", ")
        expanded_source = source.expansion(text, start_offset, expansion, local_by_name.keys)
        convert_statements(expanded_source.statements, expanded_source, local_by_name.dup)
      end
    end

    # A parameter destructured by the block (`|name, (parent, label)|`) is an array of names.
    def loop_parameters(block)
      parameters = block.parameters&.parameters
      return unless parameters in {optionals: [], rest: nil, posts: [], keywords: [], keyword_rest: nil, block: nil}

      parameters.requireds.map { |parameter| loop_parameter(parameter) || (return nil) }
    end

    def loop_parameter(parameter)
      case parameter
      when Prism::RequiredParameterNode then parameter.name
      when Prism::MultiTargetNode
        return unless parameter.rest.nil? && parameter.rights.empty?

        parameter.lefts.map { |left| loop_parameter(left) || (return nil) }
      end
    end

    # The value of each parameter, for each element: Ruby splats what the loop yields over several parameters,
    # or over a single destructured one.
    def literal_bindings(collection, parameters, method_name)
      collection = collection.receiver while collection.is_a?(Prism::CallNode) && collection.name == :freeze
      return unless static?(collection)

      single_name = parameters.first if parameters.size == 1 && parameters.first.is_a?(Symbol)
      case collection
      when Prism::ArrayNode
        return if method_name == :each_pair

        collection.elements.map do |element|
          next {single_name => loop_value(element)} if single_name

          bind(parameters, element.is_a?(Prism::ArrayNode) ? element.elements : [element])
        end
      when Prism::HashNode
        collection.elements.map do |association|
          pair = [association.key, association.value]
          next bind(parameters, pair) unless single_name

          {single_name => LoopValue.new(source: "[#{pair.map { |node| loop_value(node).source }.join(", ")}]", text: nil)}
        end
      end
    end

    def bind(parameters, values, value_by_name = {})
      parameters = parameters.first if parameters.size == 1 && parameters.first.is_a?(Array)
      parameters.each_with_index do |parameter, index|
        value = values[index]
        if parameter.is_a?(Symbol)
          value_by_name[parameter] = value ? loop_value(value) : LoopValue.new(source: "nil", text: nil)
        else
          bind(parameter, value.is_a?(Prism::ArrayNode) ? value.elements : [value].compact, value_by_name)
        end
      end
      value_by_name
    end

    def static?(node)
      case node
      when Prism::ArrayNode then node.elements.all? { |element| static?(element) }
      when Prism::HashNode
        node.elements.all? do |element|
          element.is_a?(Prism::AssocNode) && static?(element.key) && static?(element.value)
        end
      else STATIC_NODES.any? { |node_class| node.is_a?(node_class) }
      end
    end

    def loop_value(node)
      case node
      when Prism::SymbolNode then LoopValue.new(source: node.unescaped.to_sym.inspect, text: node.unescaped)
      when Prism::StringNode then LoopValue.new(source: node.unescaped.inspect, text: node.unescaped)
      else LoopValue.new(source: node.slice, text: nil)
      end
    end

    # A string's interpolated value is written as text when only a plain string or symbol reads it: in a regexp,
    # a command, a %W array or after a delimiter such as %Q/, the same text would mean something else.
    INLINE_OPENING = /\A(?::?"|<<|%Q?[(\[{<])/

    def substitutions(node, value_by_name, depth = 0, edits = [], inline: false)
      case node
      when Prism::LocalVariableReadNode
        value = value_by_name[node.name] if node.depth == depth
        edits << [node.location.start_offset, node.location.end_offset, value.source] if value
        return edits
      when Prism::CallNode
        if (node in {name: :to_s, arguments: nil, receiver: Prism::LocalVariableReadNode[depth: ^depth, name:]}) &&
            (text = value_by_name[name]&.text)
          return edits << [node.location.start_offset, node.location.end_offset, text.inspect]
        end
      when Prism::EmbeddedStatementsNode
        if inline && (node in {statements: {body: [Prism::LocalVariableReadNode[depth: ^depth, name:]]}})
          text = value_by_name[name]&.text
          if text&.match?(%r{\A[\w ./-]*\z})
            edits << [node.location.start_offset, node.location.end_offset, text]
            return edits
          end
        end
      when Prism::InterpolatedStringNode, Prism::InterpolatedSymbolNode
        inline = INLINE_OPENING.match?(node.opening.to_s)
      when Prism::InterpolatedRegularExpressionNode, Prism::InterpolatedMatchLastLineNode, Prism::InterpolatedXStringNode
        inline = false
      when Prism::BlockNode, Prism::LambdaNode then depth += 1
      when Prism::DefNode then return edits
      end
      node&.compact_child_nodes&.each { |child| substitutions(child, value_by_name, depth, edits, inline:) }
      edits
    end

    def note(source, line, message)
      message += " (#{source.expansion_description})" if source.expansion_description
      notes << Note.new(path: source.path, line:, message:)
    end

    def summary(node)
      first_line = node.slice.lines.first.strip
      (first_line.length > 60) ? "#{first_line[0, 57]}..." : first_line
    end

    def render
      modules = namespace.to_s.split("::")
      depth = modules.size
      body = entries.map do |entry|
        lines = entry.is_a?(Definition) ? entry.lines : entry
        indent(lines, depth + 1).join("\n")
      end

      ruby = +"# frozen_string_literal: true\n\n"
      modules.each_with_index { |name, index| ruby << "#{"  " * index}module #{name}\n" }
      ruby << "#{"  " * depth}class Breadcrumbs < Crumbly::Trail\n"
      if helper_methods.any?
        body << "#{"  " * (depth + 1)}private"
        body.concat(helper_methods.map { |lines| indent(lines, depth + 1).join("\n") })
      end
      ruby << body.join("\n\n") << "\n" if body.any?
      ruby << "#{"  " * depth}end\n"
      depth.downto(1) { |index| ruby << "#{"  " * (index - 1)}end\n" }
      ruby
    end

    def indent(lines, depth)
      lines.map { |line| line.empty? ? line : "#{"  " * depth}#{line}" }
    end
  end
end
