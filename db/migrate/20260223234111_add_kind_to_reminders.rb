class AddKindToReminders < ActiveRecord::Migration[8.1]
  def change
    add_column :reminders, :kind, :string, null: false, default: "reminder"
  end
end
