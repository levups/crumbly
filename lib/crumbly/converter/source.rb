# frozen_string_literal: true

module Crumbly
  class Converter
    # A parsed breadcrumbs file, or one expansion of a loop in it, and the edits that turn its nodes into text.
    class Source
      MAGIC_COMMENT = /\A#\s*(frozen_string_literal|encoding|coding|warn_indent|shareable_constant_value):/

      attr_reader :path, :start_offset, :expansion_description

      def self.parse(text, path:, start_offset: 0, expansion_description: nil, local_names: [])
        result = Prism.parse(text, scopes: [local_names])
        if result.failure?
          error = result.errors.first
          raise ArgumentError, "#{path}:#{error.location.start_line}: #{error.message}"
        end

        new(text, result, path:, start_offset:, expansion_description:)
      end

      def initialize(text, result, path:, start_offset:, expansion_description:)
        @text = text
        @result = result
        @path = path
        @start_offset = start_offset
        @expansion_description = expansion_description
      end

      def statements
        @result.value.statements.body
      end

      def comments
        @comments ||= @result.comments.reject { |comment| comment.slice.match?(MAGIC_COMMENT) }
      end

      def comment_lines(from_offset, to_offset)
        comments.select { |comment| comment.location.start_offset.between?(from_offset, to_offset - 1) }
          .flat_map { |comment| self.class.comment_text(comment) }
      end

      # The lines of a comment. An =begin block must start at column 0, which the class body indents: its lines
      # become # comments.
      def self.comment_text(comment)
        return [comment.slice.rstrip] unless comment.is_a?(Prism::EmbDocComment)

        comment.slice.lines[1...-1].map { |line| "# #{line.rstrip}".rstrip }
      end

      # Blanks everything before the expanded text, so that its lines and columns stay those of this file.
      def expansion(expanded_text, start_offset, description, local_names)
        padding = @text.byteslice(0, start_offset).gsub(/[^\n]/) { |character| " " * character.bytesize }
        self.class.parse(padding + expanded_text, path:, start_offset:, expansion_description: description,
          local_names:)
      end

      def rewrite(from_offset, to_offset, edits)
        rewritten = +""
        offset = from_offset
        edits.sort_by(&:first).each do |edit_start, edit_end, replacement|
          rewritten << @text.byteslice(offset, edit_start - offset) << replacement
          offset = edit_end
        end
        rewritten << @text.byteslice(offset, to_offset - offset)
      end

      # The text of a node with its continuation lines dedented, as if the node started at column 0.
      def fragment(node, edits)
        location = node.location
        text = rewrite(location.start_offset, location.end_offset, edits)
        first_line, *other_lines = text.split("\n", -1)
        dedent = /\A {0,#{location.start_column}}/
        [first_line, *other_lines.map { |line| line.sub(dedent, "") }].join("\n")
      end
    end
  end
end
