class CreatePendingInteractions < ActiveRecord::Migration[8.1]
  def change
    create_table :pending_interactions do |t|
      t.references :user, null: false, foreign_key: true
      t.string     :kind, null: false
      t.jsonb      :context, null: false, default: {}
      t.datetime   :expires_at, null: false

      t.timestamps
    end

    add_index :pending_interactions, [ :user_id, :kind ]
  end
end
