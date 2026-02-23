class CreateReminders < ActiveRecord::Migration[8.1]
  def change
    create_table :reminders do |t|
      t.references :user, null: false, foreign_key: true
      t.references :voice_command, null: true, foreign_key: true
      t.text :message
      t.datetime :fire_at
      t.boolean :recurs_daily, null: false, default: false
      t.string :status, null: false, default: "pending"

      t.timestamps
    end
  end
end
