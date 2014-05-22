module SpreeYandexMarket
  class Engine < Rails::Engine
    isolate_namespace Spree
    engine_name 'spree_yandex_market'

    initializer 'spree_yandex_market.preferences', :before => :load_config_initializers do |app|
      SpreeYandexMarket::Config = Spree::YandexMarketSettings.new

      #if Spree::Config.has_preference? :show_raw_product_description
      #  Spree::Config[:show_raw_product_description] = SpreeYandexMarket::Config[:enabled]
      #end
    end

    config.autoload_paths += %W(#{config.root}/lib)

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../app/**/*_decorator*.rb')) do |c|
        Rails.application.config.cache_classes ? require(c) : load(c)
      end

      Dir.glob(File.join(File.dirname(__FILE__), '../app/overrides/**/*.rb')) do |c|
        Rails.application.config.cache_classes ? require(c) : load(c)
      end
    end

    config.to_prepare &method(:activate).to_proc
  end
end
