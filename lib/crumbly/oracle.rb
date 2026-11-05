# frozen_string_literal: true

require "gretel"
require "crumbly"

module Crumbly
  # Compares gretel's trail with Crumbly's for the same crumbs, from a test of an app that still bundles gretel.
  module Oracle
    Difference = Data.define(:target, :arguments, :gretel, :crumbly, :page) do
      def initialize(target:, arguments:, gretel:, crumbly:, page: nil)
        super
      end

      def to_s
        call = target ? "breadcrumb #{Oracle.format_call(target, arguments)}" : "no breadcrumb call"
        "#{"#{page}, " if page}#{call}\n" \
          "  gretel:     #{format_trail(gretel)}\n" \
          "  crumbly: #{format_trail(crumbly)}"
      end

      private

      def format_trail(trail)
        return "(none)" if trail.empty?

        trail.map { |label, url| url ? "#{label} (#{url})" : label }.join(" > ")
      end
    end

    RedundantCall = Data.define(:page, :target, :arguments) do
      def to_s
        "#{page}, breadcrumb #{Oracle.format_call(target, arguments)}: the action derives the same trail"
      end
    end

    # Prepended to the view helpers by `watch`: each page the tests render compares its trail with gretel's.
    module Watch
      def breadcrumb_trail
        return super if @crumbly_trail || !Oracle.watching?

        levels = super
        Oracle.observe(self, @crumbly_breadcrumb, levels)
        levels
      end
    end

    @differences = Set.new
    @redundant_calls = Set.new
    @mutex = Mutex.new
    @watching = false

    class << self
      attr_reader :differences, :redundant_calls

      # `cases` lists what views pass to `breadcrumb`: `[[:orders], [:order, order], [order]]`.
      def compare(view, trail_class, cases)
        ::Gretel::Crumbs.reload_if_needed
        cases.filter_map do |target, *arguments|
          gretel = gretel_trail(view, target, arguments)
          crumbly = crumbly_trail(view, trail_class, target, arguments)
          Difference.new(target:, arguments:, gretel:, crumbly:) unless gretel == crumbly
        end
      end

      # From then on, or for the block, each trail a view renders is compared with the one gretel draws for its
      # `breadcrumb` call (nothing, without one). The differences go to `differences`, and the calls whose trail
      # the action derives anyway to `redundant_calls`.
      def watch
        ViewHelpers.prepend(Watch) unless ViewHelpers <= Watch
        watching = @watching
        @watching = true
        return unless block_given?

        begin
          yield
        ensure
          @watching = watching
        end
      end

      def watching?
        @watching
      end

      def observe(view, breadcrumb_call, levels)
        ::Gretel::Crumbs.reload_if_needed
        target, arguments = breadcrumb_call
        page = "#{view.controller.controller_path}##{view.controller.action_name}"
        gretel = target ? gretel_trail_or_error(view, target, arguments) : []
        difference = Difference.new(target:, arguments:, gretel:, crumbly: flatten(levels), page:)
        redundant = target && derived_trail(view) == gretel
        @mutex.synchronize do
          differences << difference unless difference.gretel == difference.crumbly
          redundant_calls << RedundantCall.new(page:, target:, arguments:) if redundant
        end
      end

      # gretel renders each link of a crumb as a level of its own; Crumbly keeps the extra ones in `links`.
      def gretel_trail(view, target, arguments)
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

      def crumbly_trail(view, trail_class, target, arguments)
        flatten(trail_class.resolve(view, target, *arguments))
      end

      def format_call(target, arguments)
        [target, *arguments].map { |argument| format_argument(argument) }.join(", ")
      end

      private

      # A call gretel cannot draw (a crumb renamed during the migration) is a difference, not a failing test.
      def gretel_trail_or_error(view, target, arguments)
        gretel_trail(view, target, arguments)
      rescue => exception
        [["gretel raised #{exception.class}: #{exception.message}", nil]]
      end

      def flatten(levels)
        levels.flat_map do |level|
          [[level.label.to_s, level.url], *level.links.map { |link| [link.label.to_s, link.url] }]
        end
      end

      # A derived trail that raises (an action loading no record, say) only means the call has to stay.
      def derived_trail(view)
        flatten(Crumbly.trail_class_for(view.controller.class).derive(view))
      rescue
        nil
      end

      def format_argument(argument)
        argument.respond_to?(:model_name) ? "#<#{argument.class.name} #{argument.to_param}>" : argument.inspect
      end
    end
  end
end
