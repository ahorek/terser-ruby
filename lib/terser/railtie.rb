# frozen_string_literal: true

require 'rails/railtie'

class Terser
  # Railtie for Rails
  class Railtie < ::Rails::Railtie
    initializer :terser, :group => :all do |_|
      config.assets.configure do |env|
        env.register_compressor 'application/javascript', :terser, Terser::Compressor
      end
    end
  end
end
