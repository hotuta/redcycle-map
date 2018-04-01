class Redcycle < ApplicationRecord
  def self.get_redcycle
    session = Capybara::Session.new(:chrome)
    login(session)
    get_cycle_port(session)
  end
end

private

def login(session)
  session.visit 'https://tcc.docomo-cycle.jp/cycle/TYO/cs_web_main.php'
  session.fill_in 'MemberID', with: Base64.strict_decode64(ENV['REDCYCLE_ID'])
  session.fill_in 'Password', with: Base64.strict_decode64(ENV['REDCYCLE_PW'])
  session.click_button 'ログイン'
end

def get_cycle_port(session)
  session.click_link '駐輪場から選ぶ'
  area_id = session.all('#AreaID option')

  area_id.count.times do |area_count|
    wait_for_ajax(session)
    wait_has_css(session, '.main_inner_wide')
    # FIXME: 画面が切り替わってsessionが変わってしまう:sob:
    session.select session.all('#AreaID option')[area_count].text, from: 'AreaID'

    loop do
      ports_path = session.all('.port_list_btn > div > a')
      ports_path.count.times do |port_count|
        puts ports_path[port_count].text.match(/(.*)\d台/)[1]
        puts ports_path[port_count].text.match(/.*(\d)台/)[1] + "台"
      end

      next_css_path = 'div.main_inner_wide_right > form:nth-child(1) > .button_submit[value="→　次へ/NEXT PAGE"]'
      if session.has_css?(next_css_path)
        session.find(next_css_path).click
      else
        break
      end
    end
  end
end

def wait_has_css(session, css_path)
  Timeout.timeout(30) do
    loop until session.has_css?(css_path)
  end
end

def wait_for_ajax(session)
  Timeout.timeout(30) do
    loop until finished_all_ajax_requests?(session)
  end
end

def finished_all_ajax_requests?(session)
  session.evaluate_script('jQuery.active').zero?
end
