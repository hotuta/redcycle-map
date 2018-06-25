class AddParkIdToStations < ActiveRecord::Migration[5.1]
  def change
    add_column :stations, :park_id, :string
  end
end
