class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :password_digest
      t.string :elevenlabs_voice_id
      t.decimal :lat
      t.decimal :lng
      t.string :timezone

      t.timestamps
    end
    add_index :users, :email, unique: true
  end
end
