# frozen_string_literal: true

module Crumbly
  class Railtie < Rails::Railtie
    initializer "crumbly.helpers" do
      ActiveSupport.on_load(:action_controller_base) { include Crumbly::Controller }
      ActiveSupport.on_load(:action_view) { include Crumbly::ViewHelpers }
    end
  end
end
