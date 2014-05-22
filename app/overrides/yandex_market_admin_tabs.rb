Deface::Override.new(:virtual_path => "spree/admin/shared/_configuration_menu",
                     :name => "yandex_market_admin_tabs",
                     :insert_bottom => "[data-hook='admin_configurations_sidebar_menu'], #admin_configurations_sidebar_menu[data-hook]",
                     :partial => 'spree/admin/yandex_market_settings/ya_tab')
