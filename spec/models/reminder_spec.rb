require "rails_helper"

RSpec.describe Reminder do
  describe "associations" do
    it "belongs to a user" do
      reminder = build(:reminder)

      expect(reminder.user).to be_a(User)
    end
  end

  describe "validations" do
    it "is valid with user, message, and fire_at" do
      reminder = build(:reminder)

      expect(reminder).to be_valid
    end

    it "is invalid without a user" do
      reminder = build(:reminder, user: nil)

      expect(reminder).not_to be_valid
      expect(reminder.errors[:user]).to be_present
    end

    it "is invalid without a message" do
      reminder = build(:reminder, message: nil)

      expect(reminder).not_to be_valid
      expect(reminder.errors[:message]).to be_present
    end

    it "is invalid without fire_at" do
      reminder = build(:reminder, fire_at: nil)

      expect(reminder).not_to be_valid
      expect(reminder.errors[:fire_at]).to be_present
    end
  end

  describe "enums" do
    it "defines status values" do
      expect(Reminder.statuses.keys).to match_array(%w[pending delivered cancelled])
    end
  end

  describe "kind/recurs_daily invariant" do
    it "is invalid when kind is daily_reminder but recurs_daily is false" do
      reminder = build(:reminder, kind: :daily_reminder, recurs_daily: false)

      expect(reminder).not_to be_valid
      expect(reminder.errors[:recurs_daily]).to be_present
    end

    it "is invalid when kind is reminder but recurs_daily is true" do
      reminder = build(:reminder, kind: :reminder, recurs_daily: true)

      expect(reminder).not_to be_valid
      expect(reminder.errors[:recurs_daily]).to be_present
    end

    it "is invalid when kind is timer but recurs_daily is true" do
      reminder = build(:reminder, kind: :timer, recurs_daily: true)

      expect(reminder).not_to be_valid
      expect(reminder.errors[:recurs_daily]).to be_present
    end

    it "is valid when kind is daily_reminder and recurs_daily is true" do
      reminder = build(:reminder, kind: :daily_reminder, recurs_daily: true)

      expect(reminder).to be_valid
    end
  end

  describe "defaults" do
    it "defaults to pending status" do
      reminder = build(:reminder)

      expect(reminder.status).to eq("pending")
    end
  end
end
