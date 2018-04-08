class CreateStations < ActiveRecord::Migration[5.1]
  def change
    create_table :stations do |t|
      t.text :numbering
      t.text :name
      t.integer :bike_number

      t.timestamps
    end
    add_index :stations, [:numbering], unique: true
  end
end
