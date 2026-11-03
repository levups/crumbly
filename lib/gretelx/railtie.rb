# frozen_string_literal: true

module GretelX
  class Railtie < Rails::Railtie
    initializer "gretelx.helpers" do
      ActiveSupport.on_load(:action_controller_base) { include GretelX::Controller }
      ActiveSupport.on_load(:action_view) { include GretelX::ViewHelpers }
    end
  end
end
