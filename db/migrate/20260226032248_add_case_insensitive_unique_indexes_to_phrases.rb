class AddCaseInsensitiveUniqueIndexesToPhrases < ActiveRecord::Migration[8.1]
  def up
    remove_index :command_aliases, [:user_id, :phrase]
    execute <<~SQL
      CREATE UNIQUE INDEX index_command_aliases_on_user_id_and_lower_phrase
        ON command_aliases (user_id, LOWER(phrase));
    SQL

    remove_index :looping_reminders, [:user_id, :stop_phrase]
    execute <<~SQL
      CREATE UNIQUE INDEX index_looping_reminders_on_user_id_and_lower_stop_phrase
        ON looping_reminders (user_id, LOWER(stop_phrase));
    SQL
  end

  def down
    execute "DROP INDEX index_command_aliases_on_user_id_and_lower_phrase"
    add_index :command_aliases, [:user_id, :phrase], unique: true

    execute "DROP INDEX index_looping_reminders_on_user_id_and_lower_stop_phrase"
    add_index :looping_reminders, [:user_id, :stop_phrase], unique: true
  end
end
