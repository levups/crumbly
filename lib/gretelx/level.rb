# frozen_string_literal: true

module GretelX
  Level = Data.define(:label, :url, :links, :current) do
    def current?
      current
    end
  end
end
