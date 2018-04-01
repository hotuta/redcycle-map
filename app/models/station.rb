class Station < ApplicationRecord
  has_many :bike_numbers

  @session = Capybara::Session.new(:chrome)

  def self.edit_mymaps
    self.get_station
    get_maps
    parse_and_edit_kml
    export_kmz
  end

  def self.get_station
    login
    get_cycle_port
  end
end

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
end

def parse_and_edit_kml
  file = File.read("map/doc.kml")
  @doc = Nokogiri::XML(file)
  @doc.remove_namespaces!

  station_names = @doc.xpath('//Folder/Placemark/name')
  style_urls = @doc.xpath('//Folder//styleUrl')

  station_names.zip(style_urls).each do |station_name, style_url|
    station_numbering = station_name.content.match(/[A-Z][0-9]+-[0-9]+/)
    find_numbering = Station.find_by(numbering: station_numbering[0])
    if station_numbering && find_numbering
      bike_number = find_numbering.bike_numbers.first.number
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
          station.name = ports_path[port_count].text.match(/(.*)\d台/)[1]
          bike_number = station.bike_numbers.build
          bike_number.number = ports_path[port_count].text.match(/.*(\d)台/)[1]
          stations << station
        else
          next
        end
      end

      Station.import stations, recursive: true, on_duplicate_key_update: [:numbering]

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
