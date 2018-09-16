require 'clockwork'
require './config/boot'
require './config/environment'

module Clockwork
  handler do |job|
    puts "Running #{job}"
  end

  every(1.days, 'Get station') do
    Station.get_station
  end

  every(10.minute, 'Update bike number') do
    Mymap.update
  end
end
