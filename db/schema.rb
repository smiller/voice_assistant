# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_02_26_005349) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "command_aliases", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "looping_reminder_id", null: false
    t.string "phrase", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["looping_reminder_id"], name: "index_command_aliases_on_looping_reminder_id"
    t.index ["user_id", "phrase"], name: "index_command_aliases_on_user_id_and_phrase", unique: true
    t.index ["user_id"], name: "index_command_aliases_on_user_id"
  end

  create_table "looping_reminders", force: :cascade do |t|
    t.boolean "active", default: false, null: false
    t.datetime "created_at", null: false
    t.integer "interval_minutes", null: false
    t.text "message", null: false
    t.integer "number", null: false
    t.string "stop_phrase", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "number"], name: "index_looping_reminders_on_user_id_and_number", unique: true
    t.index ["user_id", "stop_phrase"], name: "index_looping_reminders_on_user_id_and_stop_phrase", unique: true
    t.index ["user_id"], name: "index_looping_reminders_on_user_id"
  end

  create_table "pending_interactions", force: :cascade do |t|
    t.jsonb "context", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "kind", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id", "kind"], name: "index_pending_interactions_on_user_id_and_kind"
    t.index ["user_id"], name: "index_pending_interactions_on_user_id"
  end

  create_table "reminders", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "fire_at", null: false
    t.string "kind", default: "reminder", null: false
    t.text "message"
    t.boolean "recurs_daily", default: false, null: false
    t.string "status", default: "pending", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["status", "fire_at"], name: "index_reminders_on_status_and_fire_at"
    t.index ["user_id"], name: "index_reminders_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "api_token"
    t.datetime "created_at", null: false
    t.string "elevenlabs_voice_id"
    t.string "email", null: false
    t.decimal "lat"
    t.decimal "lng"
    t.string "password_digest"
    t.string "timezone"
    t.datetime "updated_at", null: false
    t.index ["api_token"], name: "index_users_on_api_token", unique: true
    t.index ["email"], name: "index_users_on_email", unique: true
  end

  create_table "voice_commands", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "intent", default: "unknown", null: false
    t.jsonb "params", default: {}, null: false
    t.string "status", default: "received", null: false
    t.text "transcript"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["status"], name: "index_voice_commands_on_status"
    t.index ["user_id"], name: "index_voice_commands_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "command_aliases", "looping_reminders"
  add_foreign_key "command_aliases", "users"
  add_foreign_key "looping_reminders", "users"
  add_foreign_key "pending_interactions", "users"
  add_foreign_key "reminders", "users"
  add_foreign_key "voice_commands", "users"
end
