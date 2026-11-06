# frozen_string_literal: true

require "active_support/core_ext/string/filters"
require "active_support/core_ext/string/output_safety"
require "json"
require "loofah"

module Crumbly
  # A schema.org BreadcrumbList, as Google's Rich Results test reads it.
  module JsonLd
    # A scheme is case-insensitive: HTTPS://example.com is absolute too.
    ABSOLUTE_URL = %r{\Ahttps?://}i

    class << self
      def call(levels)
        list_items = []
        levels.each do |level|
          # Google requires an item on every ListItem but the last: a level without a page is left out.
          next unless level.url || level.current?

          list_item = {"@type" => "ListItem", "position" => list_items.size + 1, "name" => plain_text(level.label)}
          if level.url
            return relative_url(level) unless ABSOLUTE_URL.match?(level.url)

            list_item["item"] = level.url
          end
          list_items << list_item
        end
        return if list_items.empty?

        {"@context" => "https://schema.org", "@type" => "BreadcrumbList", "itemListElement" => list_items}
      end

      private

      # A label read from bytes that are not UTF-8 gets replacement characters, instead of failing the page.
      def plain_text(label)
        text = label.to_s
        text = text.scrub unless text.valid_encoding?
        return text.squish unless label.html_safe?

        Loofah.html5_fragment(text).scrub!(:prune).text(encode_special_chars: false).squish
      end

      def relative_url(level)
        exception = RelativeUrl.new("JSON-LD needs absolute URLs: #{plain_text(level.label).inspect} links to " \
                                    "#{level.url}, use a _url helper in its crumb")
        raise exception if Crumbly.raise_on_relative_url?

        ActiveSupport.error_reporter.report(exception, handled: true)
        nil
      end
    end
  end
end
