# frozen_string_literal: true

module Gretel
  module Ngg
    class Railtie < Rails::Railtie
      initializer "gretel_ngg.helpers" do
        ActiveSupport.on_load(:action_controller_base) { include Gretel::Ngg::Controller }
        ActiveSupport.on_load(:action_view) { include Gretel::Ngg::ViewHelpers }
      end
    end
  end
end
