class CreateLoopingReminders < ActiveRecord::Migration[8.1]
  def change
    create_table :looping_reminders do |t|
      t.references :user, null: false, foreign_key: true
      t.integer    :number, null: false
      t.integer    :interval_minutes, null: false
      t.text       :message, null: false
      t.string     :stop_phrase, null: false
      t.boolean    :active, null: false, default: false

      t.timestamps
    end

    add_index :looping_reminders, [ :user_id, :number ], unique: true
    add_index :looping_reminders, [ :user_id, :stop_phrase ], unique: true
  end
end
