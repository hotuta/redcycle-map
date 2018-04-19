Rails.application.config.to_prepare do
  Capybara.register_driver :selenium do |app|
    Capybara::Selenium::Driver.new(app, browser: :chrome)
  end

  Capybara.configure do |config|
    config.default_driver = :selenium
    config.default_max_wait_time = 5
  end
end
