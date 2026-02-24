class AddDbConstraintsAndIndexes < ActiveRecord::Migration[8.1]
  def change
    change_column_null :reminders, :fire_at, false
    change_column_null :voice_commands, :status, false
    change_column_default :voice_commands, :status, from: nil, to: "received"
    change_column_null :voice_commands, :intent, false
    change_column_default :voice_commands, :intent, from: nil, to: "unknown"

    add_index :reminders, [ :status, :fire_at ]
    add_index :voice_commands, :status
  end
end
