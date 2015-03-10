# -*- coding: utf-8 -*-
require 'nokogiri'

module Export
  class YandexMarketExporter
    include Spree::Core::Engine.routes.url_helpers
    #ActionController::UrlWriter
    attr_accessor :host, :currencies
    
    DEFAULT_OFFER = "simple"

    def helper
      @helper ||= ApplicationController.helpers
    end
    
    def export
      @config = Spree::YandexMarketSettings.new
      @host = @config.preferred_url.sub(%r[^http://],'').sub(%r[/$], '')
      ActionController::Base.asset_host = @config.preferred_url
      
      @currencies = @config.preferred_currency.split(';').map{|x| x.split(':')}
      @currencies.first[1] = 1
      @categories = []
      cat_names = @config.preferred_category.split(', ')
      cat_names.each do |cat_name|
        cat = Spree::Taxon.find_by_name(cat_name)
        @categories += cat.self_and_descendants if cat
      end
      @categories.uniq!
      #@preferred_category = Taxon.find_by_name(@config.preferred_category)
      #@categories = @preferred_category.self_and_descendants
      @categories_ids = @categories.collect { |x| x.id }
      
      # Nokogiri::XML::Builder.new({ :encoding =>"utf-8"}, SCHEME) do |xml|
      Nokogiri::XML::Builder.new(:encoding =>"utf-8") do |xml|
        xml.doc.create_internal_subset('yml_catalog',
                                       nil,
                                       "shops.dtd"
                                       )

        xml.yml_catalog(:date => Time.now.to_s(:ym)) {
          
          xml.shop { # описание магазина
            xml.name    @config.preferred_short_name
            xml.company @config.preferred_full_name
            xml.url     path_to_url('')
            
            xml.currencies { # описание используемых валют в магазине
              @currencies && @currencies.each do |curr|
                opt = {:id => curr.first, :rate => curr[1] }
                opt.merge!({ :plus => curr[2]}) if curr[2] && ["CBRF","NBU","NBK","CB"].include?(curr[1])
                xml.currency(opt)
              end
            }        
            
            xml.categories { # категории товара
              @categories_ids && @categories.each do |cat|
                @cat_opt = { :id => cat.id }
                @cat_opt.merge!({ :parentId => cat.parent_id}) unless cat.parent_id.blank?
                xml.category(@cat_opt){ xml  << cat.name }
              end
            }
            xml.offers { # список товаров
              if @categories_ids.present?
                products = Spree::Product.in_taxons(@categories).active.master_price_gte(0.001)
                products.uniq!
                products = products.on_hand if @config.preferred_wares == "on_hand"
                products = products.where(:export_to_yandex_market => true).visible
                products.find_in_batches(:batch_size => 500) do |group|
                  group.each do |product|
                    taxon = product.taxons.where(:id => @categories_ids).first
                    if taxon
                      offer(xml, product, product.master, taxon)
                      #if product.has_variants?
                      #  product.variants.each do |variant|
                      #    offer(xml, product, variant, taxon)
                      #  end
                      #else
                      #  offer(xml, product, product.master, taxon)
                      #end
                    end
                  end
                end
              end
            }
          }
        } 
      end.to_xml
      
    end
    
    
    private
    # :type => "book"
    # :type => "audiobook"
    # :type => misic
    # :type => video
    # :type => tour
    # :type => event_ticket

    def delivery_cost(product)
      return 0.0 unless product.price
      if (product.price ).abs >= Spree::Order::MIN_FREE_ORDER_PRICE
        0.0
      else
        Spree::Order::DEFAULT_DELIVERY_COST
      end
    end

    # product name = type + brand + product.name + артикул
    def product_name(product)
      name = ''
      properties = product.property_name_and_value
      properties_names = %w(type brand)
      properties_names.each do |property_name|
        if properties.include? property_name
          name += properties[property_name] + ' ' unless properties[property_name].nil?
        end
      end
      name += product.name
      if product.sku.present?
        name += ", артикул: #{product.sku}"
      end
      name
    end

    def path_to_url(path)
      "http://#{@host.sub(%r[^http://],'')}/#{path.sub(%r[^/],'')}"
    end
    
    def offer(xml, product, variant, cat)
      
      product_properties = { }
      product.product_properties.map {|x| product_properties[x.property_name] = x.value }
      wares_type_value = product_properties[@config.preferred_wares_type]
      if ["book", "audiobook", "music", "video", "tour", "event_ticket", "vendor_model"].include? wares_type_value
        send("offer_#{wares_type_value}".to_sym, xml, product, variant, cat)
      else
        send("offer_#{DEFAULT_OFFER}".to_sym, xml, product, variant, cat)
      end
    end
    
    # общая часть для всех видов продукции
    def shared_xml(xml, product, variant, cat)
      xml.url product_url(product, host: @host, protocol: :http) + "/?utm_source=market.yandex.ru&amp;utm_term=#{product.id}"
      xml.price product.price
      xml.currencyId @currencies.first.first
      xml.categoryId cat.id
      if variant.images.any?
        xml.picture path_to_url(variant.images.first.attachment.url(:product, false))
      elsif product.main_image.present?
        xml.picture path_to_url(product.main_image.attachment.url(:product, false))
      end
      variant.option_values.each do |option_value|
        xml.param(option_value.presentation, :name => option_value.option_type.presentation)
      end
    end

    # Обычное описание
    def offer_vendor_model(xml, product, variant, cat)
      product_properties = { }
      product.product_properties.map {|x| product_properties[x.property_name] = x.value }
      opt = { :id => product.id, :type => "vendor.model", :available => product.has_stock? }
      xml.offer(opt) {
        shared_xml(xml, product, variant, cat)
        # xml.delivery               !product.shipping_category.blank?
        # На самом деле наличие shipping_category не обязательно должно быть чтобы была возможна доставка
        # смотри http://spreecommerce.com/documentation/shipping.html#shipping-category
        xml.delivery               true
        xml.local_delivery_cost    delivery_cost product
        xml.typePrefix             product_properties[@config.preferred_type_prefix] if product_properties[@config.preferred_type_prefix]
        xml.name                   product_name product
        xml.vendor                 product_properties[@config.preferred_vendor] if product_properties[@config.preferred_vendor]
        xml.vendorCode             product_properties[@config.preferred_vendor_code] if product_properties[@config.preferred_vendor_code]
        xml.model                  product_properties[@config.preferred_model] if product_properties[@config.preferred_model]
        xml.description            product.description if product.description
        xml.manufacturer_warranty  !product_properties[@config.preferred_manufacturer_warranty].blank? 
        xml.country_of_origin      product_properties[@config.preferred_country_of_manufacturer] if product_properties[@config.preferred_country_of_manufacturer]
        xml.downloadable           false
      }
    end

    # простое описание
    def offer_simple(xml, product, variant, cat)
      product_properties = { }
      product.product_properties.map {|x| product_properties[x.property_name] = x.value }
      opt = { :id => product.id,  :available => product.has_stock?, :type => "vendor.model" }
      xml.offer(opt) {
        shared_xml(xml, product, variant, cat)
        xml.delivery            true
        xml.local_delivery_cost delivery_cost(product)
        xml.typePrefix          product.product_type
        xml.vendor              product.brand
        xml.vendorCode          product.sku
        xml.model               product.name
        xml.description         product.description
        xml.country_of_origin   product_properties[@config.preferred_country_of_manufacturer]
        xml.downloadable        false
      }
    end
    
    # Книги
    def offer_book(xml, product, variant, cat)
      product_properties = { }
      product.product_properties.map {|x| product_properties[x.property_name] = x.value }
      opt = { :id => product.id, :type => "book", :available => product.has_stock? }
      xml.offer(opt) {
        shared_xml(xml, product, variant, cat)
        
        xml.delivery true
        xml.local_delivery_cost @config.preferred_local_delivery_cost
        
        xml.author product_properties[@config.preferred_author]
        xml.name product.name
        xml.publisher product_properties[@config.preferred_publisher]
        xml.series product_properties[@config.preferred_series]
        xml.year product_properties[@config.preferred_year]
        xml.ISBN product_properties[@config.preferred_isbn]
        xml.volume product_properties[@config.preferred_volume]
        xml.part product_properties[@config.preferred_part]
        xml.language product_properties[@config.preferred_language]
        
        xml.binding product_properties[@config.preferred_binding]
        xml.page_extent product_properties[@config.preferred_page_extent]
        
        xml.description product.description
        xml.downloadable false
      }
    end
    
    # Аудиокниги
    def offer_audiobook(xml, product, variant, cat)
      product_properties = { }
      product.product_properties.map {|x| product_properties[x.property_name] = x.value }      
      opt = { :id => product.id, :type => "audiobook", :available => product.has_stock?  }
      xml.offer(opt) {  
        shared_xml(xml, product, variant, cat)
        
        xml.author product_properties[@config.preferred_author]
        xml.name product.name
        xml.publisher product_properties[@config.preferred_publisher]
        xml.series product_properties[@config.preferred_series]
        xml.year product_properties[@config.preferred_year]
        xml.ISBN product_properties[@config.preferred_isbn]
        xml.volume product_properties[@config.preferred_volume]
        xml.part product_properties[@config.preferred_part]
        xml.language product_properties[@config.preferred_language]
        
        xml.performed_by product_properties[@config.preferred_performed_by]
        xml.storage product_properties[@config.preferred_storage]
        xml.format product_properties[@config.preferred_format]
        xml.recording_length product_properties[@config.preferred_recording_length]
        xml.description product.description
        xml.downloadable true
        
      }
    end
    
    # Описание музыкальной продукции
    def offer_music(xml, product, variant, cat)
      product_properties = { }
      product.product_properties.map {|x| product_properties[x.property_name] = x.value }
      opt = { :id => product.id, :type => "artist.title", :available => product.has_stock?  }
      xml.offer(opt) {
        shared_xml(xml, product, variant, cat)
        xml.delivery true        

        
        xml.artist product_properties[@config.preferred_artist]
        xml.title  product_properties[@config.preferred_title]
        xml.year   product_properties[@config.preferred_music_video_year]
        xml.media  product_properties[@config.preferred_media]
        
        xml.description product.description
        
      }
    end
    
    # Описание видео продукции:
    def offer_video(xml, product, variant, cat)
      product_properties = { }
      product.product_properties.map {|x| product_properties[x.property_name] = x.value }
      opt = { :id => product.id, :type => "artist.title", :available => product.has_stock?  }
      xml.offer(opt) {
        shared_xml(xml, product, variant, cat)
        
        xml.delivery true        
        xml.title             product_properties[@config.preferred_title]
        xml.year              product_properties[@config.preferred_music_video_year]
        xml.media             product_properties[@config.preferred_media]
        xml.starring          product_properties[@config.preferred_starring]
        xml.director          product_properties[@config.preferred_director]
        xml.originalName      product_properties[@config.preferred_original_name]
        xml.country_of_origin product_properties[@config.preferred_video_country]
        xml.description       product.description
      }
    end
    
    # Описание тура
    def offer_tour(xml, product, variant, cat)
      product_properties = { }
      product.product_properties.map {|x| product_properties[x.property_name] = x.value }
      opt = { :id => product.id, :type => "tour", :available => product.has_stock?  }
      xml.offer(opt) {
        shared_xml(xml, product, variant, cat)
        
        xml.delivery true        
        xml.local_delivery_cost @config.preferred_local_delivery_cost
        xml.worldRegion ""
        xml.country ""
        xml.region ""
        xml.days ""
        xml.dataTour ""
        xml.dataTour ""
        xml.name ""
        xml.hotel_stars ""
        xml.room ""
        xml.meal ""
        xml.included ""
        xml.transport ""
        xml.description product.description
      }
    end
    
    # Описание билетов на мероприятия
    def offer_event_ticket(xml, product, variant, cat)
      product_properties = { }
      product.product_properties.map {|x| product_properties[x.property_name] = x.value }      
      opt = { :id => product.id, :type => "event-ticket", :available => product.has_stock?  }    
      xml.offer(opt) {
        shared_xml(xml, product, variant, cat)
        xml.delivery true                
        xml.local_delivery_cost @config.preferred_local_delivery_cost
        xml.name product.name
        xml.place product_properties[@config.preferred_place]
        xml.hall(:plan => product_properties[@config.preferred_hall_url_plan]) { xml << product_properties[@config.preferred_hall] }
        xml.date product_properties[@config.preferred_event_date]
        xml.is_premiere !product_properties[@config.preferred_is_premiere].blank? 
        xml.is_kids !product_properties[@config.preferred_is_kids].blank? 
        xml.description product.description
      }
    end
    
  end
end
