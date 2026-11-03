# frozen_string_literal: true

module Gretel
  module Ngg
    class Error < StandardError; end

    class DuplicateCrumb < Error; end

    class UnknownCrumb < Error; end

    class MissingTrail < Error; end

    class RelativeUrl < Error; end
  end
end
