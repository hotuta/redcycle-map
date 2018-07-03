Rails.application.config.to_prepare do
  chrome_bin = ENV.fetch('GOOGLE_CHROME_SHIM', nil)
  chrome_opts = chrome_bin ? {chromeOptions: {binary: chrome_bin}} : {}

  caps = Selenium::WebDriver::Remote::Capabilities.chrome(chrome_opts)
  Capybara.register_driver :chrome do |app|
    Capybara::Selenium::Driver.new(app, browser: :chrome, desired_capabilities: caps)
  end

  Capybara.configure do |config|
    config.default_driver = :chrome
    config.default_max_wait_time = 5
  end
end
