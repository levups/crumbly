# frozen_string_literal: true

require "gretelx"

module GretelX
  # Lists the `breadcrumb` calls of views whose trail the action now derives, for a person to review: a call
  # is only redundant when the derived trail matches the one its crumb drew.
  module DerivedCallSites
    CallSite = Data.define(:path, :line, :code, :reason) do
      def to_s
        "#{path}:#{line}: #{code} (#{reason})"
      end
    end

    BREADCRUMB_CALL = /\bbreadcrumb[ (]\s*(?<target>:\w+|@\w+)(?<arguments>[^\n%}]*)/
    VIEW_GLOB = "**/*.{erb,haml,slim,ruby}"
    FORM_CRUMBS = %w[generic_form new edit].freeze

    def self.call(*directories)
      directories.flat_map do |directory|
        Dir.glob(VIEW_GLOB, base: directory).sort.flat_map { |path| call_sites(File.join(directory, path)) }
      end
    end

    def self.call_sites(path)
      action = File.basename(path).split(".").first
      controller_name = File.basename(File.dirname(path))
      File.foreach(path).with_index(1).filter_map do |line, number|
        match = BREADCRUMB_CALL.match(line)
        reason = match && reason(match[:target], match[:arguments].strip.delete_suffix(")").strip, action, controller_name)
        CallSite.new(path:, line: number, code: match[0].strip, reason:) if reason
      end
    end

    def self.reason(target, arguments, action, controller_name)
      record = "@#{controller_name.singularize}"
      if FORM_CRUMBS.include?(target.delete_prefix(":"))
        case action
        when "new" then 'new derives "New" under the collection'
        when "edit" then 'edit derives "Edit" under the record'
        else "only new and edit views derive a form's trail"
        end
      elsif action == "show" && (target == record || (target == ":#{controller_name.singularize}" && arguments == ", #{record}"))
        "show derives the crumb of #{record}"
      elsif action == "index" && target == ":#{controller_name}" && arguments.empty?
        "index derives the #{controller_name} crumb"
      end
    end
  end
end
