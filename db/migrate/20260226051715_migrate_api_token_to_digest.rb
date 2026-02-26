class MigrateApiTokenToDigest < ActiveRecord::Migration[8.1]
  def change
    remove_column :users, :api_token, :string
    add_column :users, :api_token_digest, :string
    add_index :users, :api_token_digest, unique: true
  end
end
