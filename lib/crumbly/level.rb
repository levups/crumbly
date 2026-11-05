# frozen_string_literal: true

module Crumbly
  Level = Data.define(:label, :url, :links, :current) do
    def current?
      current
    end
  end
end
