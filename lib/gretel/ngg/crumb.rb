# frozen_string_literal: true

module Gretel
  module Ngg
    Link = Data.define(:label, :url)

    Crumb = Data.define(:label, :url, :links, :parent)
  end
end
