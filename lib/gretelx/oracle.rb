# frozen_string_literal: true

require "gretelx"

module GretelX
  # Compares gretel's trail with GretelX's for the same crumbs, from a test of an app that still bundles gretel.
  module Oracle
    Difference = Data.define(:target, :arguments, :gretel, :gretelx) do
      def to_s
        "breadcrumb #{[target, *arguments].map { |argument| format_argument(argument) }.join(", ")}\n" \
          "  gretel:     #{format_trail(gretel)}\n" \
          "  gretelx: #{format_trail(gretelx)}"
      end

      private

      def format_argument(argument)
        argument.respond_to?(:model_name) ? "#<#{argument.class.name} #{argument.to_param}>" : argument.inspect
      end

      def format_trail(trail)
        trail.map { |label, url| url ? "#{label} (#{url})" : label }.join(" > ")
      end
    end

    # `cases` lists what views pass to `breadcrumb`: `[[:orders], [:order, order], [order]]`.
    def self.compare(view, trail_class, cases)
      ::Gretel::Crumbs.reload_if_needed
      cases.filter_map do |target, *arguments|
        gretel = gretel_trail(view, target, arguments)
        gretelx = gretelx_trail(view, trail_class, target, arguments)
        Difference.new(target:, arguments:, gretel:, gretelx:) unless gretel == gretelx
      end
    end

    # gretel renders each link of a crumb as a level of its own; GretelX keeps the extra ones in `links`.
    def self.gretel_trail(view, target, arguments)
      links = []
      crumb = ::Gretel::Crumb.new(view, target, *arguments)
      while crumb
        links.unshift(*crumb.links)
        crumb = crumb.parent
      end
      if links.none? { |link| link.key == :root } && ::Gretel::Crumbs.crumb_defined?(:root)
        links.unshift(*::Gretel::Crumb.new(view, :root).links)
      end
      links.map { |link| [link.text.to_s, link.url] }
    end

    def self.gretelx_trail(view, trail_class, target, arguments)
      trail_class.resolve(view, target, *arguments).flat_map do |level|
        [[level.label.to_s, level.url], *level.links.map { |link| [link.label.to_s, link.url] }]
      end
    end
  end
end
