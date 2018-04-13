class Station < ApplicationRecord
  has_many :bike_numbers

  @session = Capybara::Session.new(:chrome)

  def self.edit_mymaps
    self.get_station
    get_maps
    parse_and_edit_kml
    export_kmz
    upload_kmz
  end

  def self.get_station
    login
    get_cycle_port
  end

  class << self
    private

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

      station_names.zip(style_urls).each do |station_name, style_url|
        station_numbering = station_name.content.match(/[A-Z][0-9]+-[0-9]+/)
        find_numbering = Station.find_by(numbering: station_numbering[0])
        if station_numbering && find_numbering
          bike_number = find_numbering.bike_number
          if bike_number == 0
            style_url.content = "#icon-ci-2"
          end
          station_name.content = "[#{bike_number}台] " + station_name.content
        else
          next
        end
      end
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

      # TODO: 既に空のレイヤーが追加されている場合は削除する

      # FIXME: sleepは暫定措置
      sleep 15
      @session.find(:id, "map-action-add-layer").click
      sleep 15
      @session.find(:id, "ly1-layerview-import-link").click
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
      @session.find(:xpath, "//div[@id='ly0-layer-header']/div[3]", visible: false).click
      sleep 15
      @session.find(:xpath, '//*[@id="layerview-menu"]/div[2]/div', visible: false).click
      sleep 15
      @session.find(:xpath, '//*[@id="cannot-undo-dialog"]/div[3]/button[1]', visible: false).click
      sleep 15
      @session.driver.quit
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

          stations = []
          ports_path.count.times do |port_count|
            station_numbering = ports_path[port_count].text.match(/[A-Z][0-9]+-[0-9]+/)
            if station_numbering
              station = Station.new
              station.numbering = station_numbering[0]
              station.name = ports_path[port_count].text.match(/(.*.\D+)\d+台/)[1]
              station.bike_number = ports_path[port_count].text.match(/\D+(\d+)台/)[1]
              # TODO:ポートのバイク台数を取得時毎に保存したい。ただ、Herokuは1万レコード制限があるので、CloudGarageにPostgreSQL鯖を立てて設定をしてから有効化する。
              # bike_number = station.bike_numbers.build
              # bike_number.number = ports_path[port_count].text.match(/.*(\d)台/)[1]
              stations << station
            else
              next
            end
          end

          Station.import stations, recursive: true, on_duplicate_key_update: {conflict_target: [:numbering], columns: [:bike_number]}

          next_css_path = 'div.main_inner_wide_right > form:nth-child(1) > .button_submit[value="→　次へ/NEXT PAGE"]'
          if @session.has_css?(next_css_path)
            @session.find(next_css_path).click
          else
            break
          end
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

