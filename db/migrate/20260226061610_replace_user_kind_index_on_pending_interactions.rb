class ReplaceUserKindIndexOnPendingInteractions < ActiveRecord::Migration[8.1]
  def change
    remove_index :pending_interactions, [ :user_id, :kind ]
    add_index :pending_interactions, [ :user_id, :expires_at ]
  end
end
