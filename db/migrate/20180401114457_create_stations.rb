class CreateStations < ActiveRecord::Migration[5.1]
  def change
    create_table :stations do |t|
      t.text :numbering
      t.text :name

      t.timestamps
    end
  end
end
