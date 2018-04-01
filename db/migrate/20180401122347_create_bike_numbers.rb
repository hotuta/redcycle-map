class CreateBikeNumbers < ActiveRecord::Migration[5.1]
  def change
    create_table :bike_numbers do |t|
      t.integer :station_id
      t.integer :number

      t.timestamps
    end
  end
end
