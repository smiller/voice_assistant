class AddActiveIndexToLoopingReminders < ActiveRecord::Migration[8.1]
  def change
    add_index :looping_reminders, :active, where: "active = true", name: "index_looping_reminders_active_true"
  end
end
