# frozen_string_literal: true

module Crumbly
  Link = Data.define(:label, :url)

  Crumb = Data.define(:label, :url, :links, :parent)
end
