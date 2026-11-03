# frozen_string_literal: true

require "prism"
require "gretel/ngg"
require_relative "converter/source"
require_relative "converter/crumb_definition"

if Gem::Version.new(Prism::VERSION) < Gem::Version.new("1.2")
  raise LoadError, "gretel-ngg-convert needs prism 1.2 or later (#{Prism::VERSION} is loaded): add gem \"prism\" " \
                   "to your Gemfile"
end

module Gretel
  module Ngg
    # Turns gretel's breadcrumbs files into one Gretel::Ngg::Trail subclass, and lists what it leaves out.
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

      LOOP_METHODS = %i[each each_pair].freeze
      STATIC_NODES = [
        Prism::SymbolNode, Prism::StringNode, Prism::IntegerNode, Prism::FloatNode,
        Prism::NilNode, Prism::TrueNode, Prism::FalseNode
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

      attr_reader :source_by_path, :namespace, :entries, :definition_by_key, :notes

      def convert_statements(statements, source)
        previous_end_offset = source.start_offset
        statements.each do |statement|
          comments = source.comment_lines(previous_end_offset, statement.location.start_offset)
          previous_end_offset = statement.location.end_offset
          convert_statement(statement, source, comments)
        rescue Unconvertible => exception
          note(source, exception.line, exception.message)
        end
      end

      def convert_statement(statement, source, comments)
        if crumb_call?(statement)
          define(CrumbDefinition.new(statement, source), source, comments)
        elsif loop_call?(statement)
          entries << comments if comments.any?
          expand_loop(statement, source)
        else
          raise Unconvertible.new("not a crumb definition, left out: #{summary(statement)}",
            statement.location.start_line)
        end
      end

      def crumb_call?(node)
        node.is_a?(Prism::CallNode) && node.receiver.nil? && node.name == :crumb
      end

      def loop_call?(node)
        node.is_a?(Prism::CallNode) && LOOP_METHODS.include?(node.name) && node.receiver &&
          node.block.is_a?(Prism::BlockNode)
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

      def expand_loop(call, source)
        block = call.block
        names = loop_parameter_names(block)
        unless names
          raise Unconvertible.new("crumbs defined in a loop whose block takes #{block.parameters&.slice.inspect}: " \
                                  "left out, write them by hand", call.location.start_line)
        end

        values_list = literal_values(call.receiver, names.size, call.name)
        unless values_list
          raise Unconvertible.new("crumbs defined in a loop over #{summary(call.receiver)}, which is not a literal: " \
                                  "left out, write them by hand", call.location.start_line)
        end

        start_offset = block.parameters ? block.parameters.location.end_offset : block.opening_loc.end_offset
        values_list.each do |values|
          value_by_name = names.zip(values).to_h
          text = source.rewrite(start_offset, block.closing_loc.start_offset, substitutions(block.body, value_by_name))
          expansion = value_by_name.map { |name, value| "#{name} = #{value.source}" }.join(", ")
          expanded_source = source.expansion(text, start_offset, expansion)
          convert_statements(expanded_source.statements, expanded_source)
        end
      end

      def loop_parameter_names(block)
        parameters = block.parameters&.parameters
        return unless parameters
        return unless parameters.optionals.empty? && parameters.rest.nil? && parameters.posts.empty? &&
          parameters.keywords.empty? && parameters.keyword_rest.nil? && parameters.block.nil?
        return unless parameters.requireds.all?(Prism::RequiredParameterNode)

        parameters.requireds.map(&:name)
      end

      def literal_values(collection, arity, method_name)
        collection = collection.receiver while collection.is_a?(Prism::CallNode) && collection.name == :freeze
        return unless static?(collection)

        case collection
        when Prism::ArrayNode
          return if method_name == :each_pair

          collection.elements.map { |element| element_values(element, arity) || (return nil) }
        when Prism::HashNode
          collection.elements.map do |association|
            key = loop_value(association.key)
            value = loop_value(association.value)
            case arity
            when 1 then [LoopValue.new(source: "[#{key.source}, #{value.source}]", text: nil)]
            when 2 then [key, value]
            else return nil
            end
          end
        end
      end

      def element_values(element, arity)
        return [loop_value(element)] if arity == 1
        return unless element.is_a?(Prism::ArrayNode)

        values = element.elements.map { |value| loop_value(value) }
        values.fill(LoopValue.new(source: "nil", text: nil), values.size...arity).first(arity)
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

      def substitutions(node, value_by_name, depth = 0, edits = [])
        case node
        when Prism::LocalVariableReadNode
          value = value_by_name[node.name] if node.depth == depth
          edits << [node.location.start_offset, node.location.end_offset, value.source] if value
          return edits
        when Prism::CallNode
          receiver = node.receiver
          if node.name == :to_s && node.arguments.nil? && receiver.is_a?(Prism::LocalVariableReadNode) &&
              receiver.depth == depth && (text = value_by_name[receiver.name]&.text)
            return edits << [node.location.start_offset, node.location.end_offset, text.inspect]
          end
        when Prism::EmbeddedStatementsNode
          read = node.statements&.body&.first if node.statements&.body&.size == 1
          if read.is_a?(Prism::LocalVariableReadNode) && read.depth == depth
            text = value_by_name[read.name]&.text
            if text&.match?(%r{\A[\w ./-]*\z})
              edits << [node.location.start_offset, node.location.end_offset, text]
              return edits
            end
          end
        when Prism::BlockNode, Prism::LambdaNode then depth += 1
        when Prism::DefNode then return edits
        end
        node&.compact_child_nodes&.each { |child| substitutions(child, value_by_name, depth, edits) }
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
        ruby << "#{"  " * depth}class Breadcrumbs < Gretel::Ngg::Trail\n"
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
end
