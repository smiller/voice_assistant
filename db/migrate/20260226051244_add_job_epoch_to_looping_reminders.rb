class AddJobEpochToLoopingReminders < ActiveRecord::Migration[8.1]
  def change
    add_column :looping_reminders, :job_epoch, :integer, default: 0, null: false
  end
end
