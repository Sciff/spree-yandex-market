# -*- coding: utf-8 -*-
require 'nokogiri'

class Export::YandexMarketWardrobeExporter < Export::YandexMarketExporter
  private

  # простое описание
  def offer_simple(xml, product, variant, cat)
    product_properties = { }
    product.product_properties.map {|x| product_properties[x.property_name] = x.value }
    if product.taxons.where(wardrobe: true).any?
      offer_simple_variant(xml, product, cat, product_properties)
    else
      opt = { :id => product.id,  :available => product.has_stock?, :type => "vendor.model" }
      xml.offer(opt) {
        shared_xml(xml, product, variant, cat)
        xml.cpa                 0
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
  end

  def offer_simple_variant(xml, product, cat, product_properties)
    product.variants.each do |variant|
      opt = { id: "#{product.id}#{variant.id}",  available: variant.in_stock?, type: "vendor.model", group_id: product.id }
      xml.offer(opt) {
        variant_shared_xml(xml, product, variant, cat)
        if variant.option_values.where.not(universal_size_id: nil).any?
          size = variant.option_values.where.not(universal_size_id: nil).first.universal_size
          xml.param(size.name, name: 'Размер', unit: size.size_type)
        end
        xml.market_category     product.taxons.pluck(:market_category).compact.first
        xml.cpa                 1
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
  end

  do

end
  def variant_shared_xml(xml, product, variant, cat)
    xml.url product_url(product, host: @host, protocol: :http) + "/?utm_source=market.yandex.ru&amp;utm_term=#{product.id}"
    xml.price variant.price
    xml.currencyId @currencies.first.first
    xml.categoryId cat.id
    if variant.images.any?
      xml.picture path_to_url(variant.images.first.attachment.url(:product, false))
    elsif product.main_image.present?
      xml.picture path_to_url(product.main_image.attachment.url(:product, false))
    end

    product.product_properties.each do |product_property|
      unless ['brand', 'type'].include? product_property.property.name.downcase
        xml.param(product_property.value, name: product_property.property.presentation.mb_chars.capitalize.to_s)
      end
    end
  end
end
