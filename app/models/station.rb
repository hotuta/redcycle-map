class Station < ApplicationRecord
  has_many :bike_numbers

  @session = Capybara::Session.new(:chrome)

  class << self
    def update_mymaps
      get_bikes
      get_maps
      parse_and_edit_kml
      export_kmz
      upload_kmz
    end

    def get_station
      login
      get_cycle_port
    end

    def get_maps
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

    def parse_and_edit_kml
      file = File.read("map/doc.kml")
      @doc = Nokogiri::XML(file)
      @doc.remove_namespaces!

      layer_name = @doc.xpath('//Folder/name').first
      layer_name.content = "#{DateTime.now.strftime('%-m月%d日%H時%M分')}現在"

      station_names = @doc.xpath('//Folder/Placemark/name')
      style_urls = @doc.xpath('//Folder//styleUrl')
      coordinates = @doc.xpath('//Folder//coordinates')

      stations = []
      station_names.zip(style_urls, coordinates).each do |station_name, style_url, coordinate|
        station_numbering = station_name.content.match(/[A-Z][0-9]+[-|‐][0-9]+/)
        find_station = Station.find_by(numbering: station_numbering[0])

        if find_station
          find_station.numbering = station_numbering[0]
          find_station.latitude = coordinate.content.match(/(\-?\d+(\.\d+)?),\s*(\-?\d+(\.\d+)?)/)[3]
          find_station.longitude = coordinate.content.match(/(\-?\d+(\.\d+)?),\s*(\-?\d+(\.\d+)?)/)[1]
          stations << find_station
        end

        if station_numbering && find_station
          bike_number = find_station.bike_number
          if bike_number == 0
            style_url.content = "#icon-ci-2"
          end
          station_name.content = "[#{bike_number}台] " + station_name.content
        else
          next
        end
      end

      Station.import stations, recursive: true, on_duplicate_key_update: {conflict_target: :numbering, columns: [:bike_number]}
    end

    def export_kmz
      f = File.new("map/doc.kml", "w")
      f << @doc.to_xml
      f.close

      Archive::Zip.archive('edit_map.kmz', 'map/.')
      Archive::Zip.extract('edit_map.kmz', './edit_map')
    end

    def upload_kmz
      @session.visit 'https://www.google.com/maps/d/edit?mid=1UBbXpP51gfUJ8UmXLy5DJpdlMZsYgr4p'
      # YAMLファイルにCookie情報をエクスポート
      # File.open('./yaml.dump', 'w') {|f| f.write(YAML.dump(@session.driver.browser.manage.all_cookies))}
      YAML.load(Base64.strict_decode64(ENV['YAML_DUMP'])).each do |d|
        @session.driver.browser.manage.add_cookie d
      end
      @session.visit 'https://www.google.com/maps/d/edit?mid=1UBbXpP51gfUJ8UmXLy5DJpdlMZsYgr4p'

      # FIXME: sleepは暫定措置
      sleep 15

      # 既に空のレイヤーが追加されている場合は削除する
      @delete_layer_xpath = "//div[@id='ly1-layer-header']/div[3]"
      @delete_has_xpath = @delete_layer_xpath
      delete_layer_has_xpath

      sleep 15
      @session.find(:id, "map-action-add-layer").click
      sleep 15
      @session.refresh
      sleep 15
      @session.find(:id, "ly1-layerview-import-link").hover.click
      sleep 15

      html = @session.driver.browser.page_source
      doc = Nokogiri::HTML(html)

      frame = doc.xpath("/html/body/div/div[2]/iframe").attribute("id").text
      @session.driver.browser.switch_to.frame frame

      filename = 'edit_map.kmz'
      file = File.join(Dir.pwd, filename)
      @session.find(:xpath, "//*[@id='doclist']/div/div[4]/div[2]/div/div[2]/div/div/div[1]/div/div[2]/input[@type='file']", visible: false).send_keys file

      @session.driver.browser.switch_to.window @session.driver.browser.window_handle

      # レイヤーを消す
      sleep 15
      @delete_layer_xpath = "//div[@id='ly0-layer-header']/div[3]"
      delete_layer_has_xpath
      sleep 15
      @session.driver.quit
      File.delete 'edit_map.kmz'
    end

    def login
      @session.visit 'https://tcc.docomo-cycle.jp/cycle/TYO/cs_web_main.php'
      @session.fill_in 'MemberID', with: Base64.strict_decode64(ENV['REDCYCLE_ID'])
      @session.fill_in 'Password', with: Base64.strict_decode64(ENV['REDCYCLE_PW'])
      @session.click_button 'ログイン'
    end

    def get_cycle_port
      @session.click_link '駐輪場から選ぶ'
      area_id = @session.all('#AreaID option')

      area_id.count.times do |area_count|
        wait_for_ajax
        wait_has_css('.main_inner_wide')
        # FIXME: 画面が切り替わってsessionが変わってしまう:sob:
        @session.select @session.all('#AreaID option')[area_count].text, from: 'AreaID'

        loop do
          ports_path = @session.all('.port_list_btn > div > a')
          park_ids_path = @session.all(".sp_view > form > input[name='ParkingID']", visible: false)

          stations = []
          ports_path.count.times do |port_count|
            station_numbering = ports_path[port_count].text.match(/[A-Z][0-9]+-[0-9]+/)
            if station_numbering
              station = Station.new
              station.numbering = station_numbering[0]
              station.name = ports_path[port_count].text.match(/(.*.\D+)\d+台/)[1]
              station.bike_number = ports_path[port_count].text.match(/\D+(\d+)台/)[1]
              station.park_id = sprintf("%08d", park_ids_path[port_count].value)
              # TODO:ポートのバイク台数を取得時毎に保存したい。ただ、Herokuは1万レコード制限があるので、CloudGarageにPostgreSQL鯖を立てて設定をしてから有効化する。
              # bike_number = station.bike_numbers.build
              # bike_number.number = ports_path[port_count].text.match(/.*(\d)台/)[1]
              stations << station
            else
              next
            end
          end

          columns = Station.column_names - ["id", "numbering", "created_at", "updated_at"]
          Station.import stations, recursive: true, on_duplicate_key_update: {conflict_target: [:numbering], columns: columns}

          next_css_path = 'div.main_inner_wide_right > form:nth-child(1) > .button_submit[value="→　次へ/NEXT PAGE"]'
          if @session.has_css?(next_css_path)
            @session.find(next_css_path).click
          else
            break
          end
        end
      end
    end

    def get_bikes
      header = {content_type: 'application/json'}
      stations = []
      Station.where(updated_at: [1.days.ago...Time.now]).each do |port|
        query_xml = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>
    <csreq>
        <msgtype>3</msgtype>
        <aplcode>#{ENV['APLCODE']}</aplcode>
        <park_id>#{port.park_id}</park_id>
        <get_num>100</get_num>
        <get_start_no>1</get_start_no>
    </csreq>"
        res = RestClient.post(ENV['API_URL'], query_xml, header) {|response| response}
        doc = Nokogiri::XML(res.body)
        station = Station.new
        station.numbering = port.numbering
        station.bike_number = doc.at('//total_num').text
        stations << station
        sleep rand(0.3..0.5)
      end

      Station.import stations, recursive: true, on_duplicate_key_update: {conflict_target: :numbering, columns: [:bike_number]}
    end

    def delete_layer_has_xpath
      5.times do
        @session.refresh
        sleep 15
        if @session.has_xpath?(@delete_has_xpath)
          puts @delete_layer_xpath
          @session.find(:xpath, @delete_layer_xpath, visible: false).hover.click
          sleep 5
          @session.all(:xpath, "//*[@id='layerview-menu']/div[2]/div", visible: false).first.hover.click
          sleep 10
          @session.find(:xpath, "//*[@id='cannot-undo-dialog']/div[3]/button[1]", visible: false).hover.click
          sleep 15
        else
          break
        end
      end
    end

    def wait_has_css(css_path)
      Timeout.timeout(30) do
        loop until @session.has_css?(css_path)
      end
    end

    def wait_for_ajax
      Timeout.timeout(30) do
        loop until finished_all_ajax_requests?
      end
    end

    def finished_all_ajax_requests?
      @session.evaluate_script('jQuery.active').zero?
    end
  end
end

