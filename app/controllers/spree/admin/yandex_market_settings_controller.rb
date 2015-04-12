# -*- coding: utf-8 -*-
class Spree::Admin::YandexMarketSettingsController < Spree::Admin::BaseController
  before_filter :get_config
  
  def show
    p @config
  end
  
  def general
    @taxons =  Spree::Taxon.not_hidden
  end
  
  def currency
  end
  
  def ware_property
    @properties = Spree::Property.all
  end
  
  def export_files
    directory = File.join(Rails.root, 'public', 'yandex_market', '**', '*')
    # нельзя вызывать стат, не удостоверившись в наличии файла!!
    @export_files =  Dir[directory].map {|x| [File.basename(x), (File.file?(x) ? File.mtime(x) : 0)] }.sort{|x,y| y.last <=> x.last }
    e = @export_files.find {|x| x.first == "yandex_market.xml" }
    @export_files.reject! {|x| x.first == "yandex_market.xml" }
    @export_files.unshift(e) unless e.blank?
  end

  def export_files_wardrobe
    directory = File.join(Rails.root, 'public', 'yandex_market_wardrobe', '**', '*')
    # нельзя вызывать стат, не удостоверившись в наличии файла!!
    @export_files =  Dir[directory].map {|x| [File.basename(x), (File.file?(x) ? File.mtime(x) : 0)] }.sort{|x,y| y.last <=> x.last }
    e = @export_files.find {|x| x.first == "yandex_market_wardrobe.xml" }
    @export_files.reject! {|x| x.first == "yandex_market_wardrobe.xml" }
    @export_files.unshift(e) unless e.blank?
  end

  def run_export
    command = %{cd #{Rails.root} && RAILS_ENV=#{Rails.env} bundle exec rake spree_yandex_market:generate_ym > log/export.log &}
    logger.info "[ yandex market ] Запуск формирование файла экспорта из блока администрирования "
    logger.info "[ yandex market ] команда - #{command} "
    system command
    flash[:notice] = "Обновите страницу через несколько минут."
    redirect_to export_files_admin_yandex_market_settings_url
  end

  def run_export_wardrobe
    command = %{cd #{Rails.root} && RAILS_ENV=#{Rails.env} bundle exec rake spree_yandex_market:generate_ym_wardrobe > log/export.log &}
    logger.info "[ yandex market ] Запуск формирование файла экспорта из блока администрирования "
    logger.info "[ yandex market ] команда - #{command} "
    system command
    flash[:notice] = "Обновите страницу через несколько минут."
    redirect_to export_files_wardrobe_admin_yandex_market_settings_url
  end
  
  def update
    if params[:preferences][:category].present?
      params[:preferences][:category] = params[:preferences][:category].join(', ')
    end
    params[:preferences].each do |name, value|
      next unless @config.has_preference?(name)
      @config[name] = value
    end
    #@config.save!
    
    respond_to do |format|
      format.html {
        redirect_to admin_yandex_market_settings_path
      }
    end
  end

  private

  def get_config
    @config = Spree::YandexMarketSettings.new
  end
end
