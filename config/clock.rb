require 'clockwork'
require './config/boot'
require './config/environment'

module Clockwork
  handler do |job|
    puts "Running #{job}"
  end

  every(10.minute, 'Station') do
    Station.edit_mymaps
  end
end
