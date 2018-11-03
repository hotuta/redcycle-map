class Mymap
  include ActiveModel::Model

  @session = Capybara::Session.new(:chrome)

  class << self
    def update
      Station.get_bikes
      get_station_map
      Station.parse_and_edit_kml
      export_kmz
      upload_kmz
    end

    def get_station_map
      # 東京自転車シェアリング ポートマップ/Tokyo Bike Share Station Map - Google My Maps
      # https://www.google.com/maps/d/u/0/viewer?mid=1L2l1EnQJhCNlm_Xxkp9RTjIj68Q

      kmz_map_url = 'https://www.google.com/maps/d/u/0/kml?mid=1L2l1EnQJhCNlm_Xxkp9RTjIj68Q'
      response = RestClient.get kmz_map_url

      f = File.new("map.kmz", "wb")
      f << response.body
      f.close

      Archive::Zip.extract('map.kmz', './map')
      File.delete 'map.kmz'
    end

    def export_kmz
      file = File.read("map/doc.kml")
      @doc = Nokogiri::XML(file)

      f = File.new("map/doc.kml", "w")
      f << @doc.to_xml
      f.close

      Archive::Zip.archive('edit_map.kmz', 'map/.')
      Archive::Zip.extract('edit_map.kmz', './edit_map')
    end

    def upload_kmz
      @session.visit 'https://www.google.com/maps/d/edit?mid=105LHUShFiBhNviCJ5RCvIley_XLl0btn'
      # YAMLファイルにCookie情報をエクスポート
      # File.open('./yaml.dump', 'w') {|f| f.write(YAML.dump(@session.driver.browser.manage.all_cookies))}
      YAML.load(Base64.strict_decode64(ENV['YAML_DUMP'])).each do |d|
        @session.driver.browser.manage.add_cookie d
      end
      @session.visit 'https://www.google.com/maps/d/edit?mid=105LHUShFiBhNviCJ5RCvIley_XLl0btn'

      # 既に空のレイヤーが追加されている場合は削除する
      @delete_layer_xpath = "//div[@id='ly1-layer-header']/div[3]"
      @delete_has_xpath = @delete_layer_xpath
      delete_layer(1, 1)

      @session.find(:id, "map-action-add-layer").click
      @session.find(:id, "ly1-layerview-import-link").hover.click

      html = @session.driver.browser.page_source
      doc = Nokogiri::HTML(html)

      frame = doc.xpath("//div[2]/iframe").attribute("id").text
      @session.driver.browser.switch_to.frame frame

      filename = 'edit_map.kmz'
      file = File.join(Dir.pwd, filename)
      @session.find(:xpath, "//*[@id='doclist']//input[@type='file']", visible: false).send_keys file
      @session.has_no_css?('#doclist')

      @session.driver.browser.switch_to.window @session.driver.browser.window_handle

      @session.has_xpath?('//*[@id="map-title-desc-bar"]/div//div[2]')

      delete_layer(1, 0)
      @session.driver.quit
      File.delete 'edit_map.kmz'
    end

    def delete_layer(check_layer_num, remove_layer_num)
      5.times do
        @session.refresh
        if @session.has_xpath?("//div[@id='ly#{check_layer_num}-layer-header']/div[3]")
          @session.find(:xpath, "//div[@id='ly#{remove_layer_num}-layer-header']/div[3]", visible: false).hover.click
          @session.all(:xpath, "//*[@id='layerview-menu']/div[2]/div", visible: false).first.hover.click
          @session.find(:xpath, "//*[@id='cannot-undo-dialog']/div[3]/button[1]", visible: false).hover.click
          @session.has_xpath?('//*[@id="map-title-desc-bar"]/div//div[2]')
        else
          break
        end
      end
    end
  end
end