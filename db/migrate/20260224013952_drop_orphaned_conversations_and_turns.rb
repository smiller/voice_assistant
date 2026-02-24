class DropOrphanedConversationsAndTurns < ActiveRecord::Migration[8.1]
  def change
    drop_table :turns do |t|
      t.text "assistant_response_text"
      t.bigint "conversation_id", null: false
      t.datetime "created_at", null: false
      t.integer "status", default: 0, null: false
      t.datetime "updated_at", null: false
      t.text "user_transcript"
      t.index [ "conversation_id" ], name: "index_turns_on_conversation_id"
    end

    drop_table :conversations do |t|
      t.datetime "created_at", null: false
      t.string "title", default: "", null: false
      t.datetime "updated_at", null: false
    end
  end
end
