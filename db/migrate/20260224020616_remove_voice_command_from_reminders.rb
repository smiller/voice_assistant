class RemoveVoiceCommandFromReminders < ActiveRecord::Migration[8.1]
  def change
    remove_reference :reminders, :voice_command, index: true, foreign_key: true
  end
end
