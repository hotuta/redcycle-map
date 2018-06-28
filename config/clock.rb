require 'clockwork'
require './config/boot'
require './config/environment'

module Clockwork
  handler do |job|
    puts "Running #{job}"
  end

  every(1.days, 'Get station') do
    Station.update_mymaps
  end

  every(10.minute, 'Update bike number') do
    Station.get_bikes
  end
end
