# frozen_string_literal: true

module GretelX
  Link = Data.define(:label, :url)

  Crumb = Data.define(:label, :url, :links, :parent)
end
