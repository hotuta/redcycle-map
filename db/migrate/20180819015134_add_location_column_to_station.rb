class AddLocationColumnToStation < ActiveRecord::Migration[5.1]
  def change
    change_table :stations do |t|
      t.decimal :latitude,  precision: 11, scale: 8
      t.decimal :longitude, precision: 11, scale: 8
    end
  end
end
