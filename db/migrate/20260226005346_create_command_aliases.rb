class CreateCommandAliases < ActiveRecord::Migration[8.1]
  def change
    create_table :command_aliases do |t|
      t.references :looping_reminder, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.string     :phrase, null: false

      t.timestamps
    end

    add_index :command_aliases, [ :user_id, :phrase ], unique: true
  end
end
