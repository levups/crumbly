# frozen_string_literal: true

module Gretel
  module Ngg
    Level = Data.define(:label, :url, :links, :current) do
      def current?
        current
      end
    end
  end
end
