# frozen_string_literal: true

module Gretel
  module Ngg
    class Error < StandardError; end

    class DuplicateCrumb < Error; end

    class UnknownCrumb < Error; end

    class MissingTrail < Error; end

    class InvalidTrail < Error; end
  end
end
