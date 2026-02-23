class CreateVoiceCommands < ActiveRecord::Migration[8.1]
  def change
    create_table :voice_commands do |t|
      t.references :user, null: false, foreign_key: true
      t.text :transcript
      t.string :intent
      t.jsonb :params, null: false, default: {}
      t.string :status

      t.timestamps
    end
  end
end
