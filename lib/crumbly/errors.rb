# frozen_string_literal: true

module Crumbly
  class Error < StandardError; end

  class DuplicateCrumb < Error; end

  class UnknownCrumb < Error; end

  class MissingTrail < Error; end

  class InvalidTrail < Error; end

  class RelativeUrl < Error; end
end
