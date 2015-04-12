Spree::Core::Engine.add_routes do
  namespace :admin do
    resource :yandex_market_settings do
      member do
        get :general
        get :currency
        get :export_files
        get :export_files_wardrobe
        get :ware_property
        get :run_export
        get :run_export_wardrobe
      end
    end
  end
end
