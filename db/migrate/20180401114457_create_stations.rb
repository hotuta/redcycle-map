class CreateStations < ActiveRecord::Migration[5.1]
  def change
    create_table :stations do |t|
      t.text :station_numbering
      t.text :station_name

      t.timestamps
    end
  end
end
