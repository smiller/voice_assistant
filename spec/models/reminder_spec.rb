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

  describe "#day_label" do
    let(:user) { build(:user, timezone: "America/New_York") }

    context "when kind is daily_reminder" do
      it "returns nil" do
        reminder = build(:reminder, kind: :daily_reminder, user: user,
                         fire_at: Time.new(2026, 2, 24, 12, 0, 0, "UTC"), recurs_daily: true)

        expect(reminder.day_label).to be_nil
      end
    end

    context "when fire_at is today in the user's timezone" do
      it "returns 'today'" do
        travel_to Time.new(2026, 2, 24, 14, 0, 0, "UTC") do  # 9:00 AM ET
          reminder = build(:reminder, user: user,
                           fire_at: Time.new(2026, 2, 24, 23, 0, 0, "UTC"))  # 6:00 PM ET

          expect(reminder.day_label).to eq("today")
        end
      end
    end

    context "when fire_at is tomorrow in the user's timezone" do
      it "returns 'tomorrow'" do
        travel_to Time.new(2026, 2, 24, 14, 0, 0, "UTC") do  # 9:00 AM ET
          reminder = build(:reminder, user: user,
                           fire_at: Time.new(2026, 2, 25, 12, 0, 0, "UTC"))  # 7:00 AM ET next day

          expect(reminder.day_label).to eq("tomorrow")
        end
      end
    end

    context "when fire_at is a later date in the user's timezone" do
      it "returns a formatted date string" do
        travel_to Time.new(2026, 2, 24, 14, 0, 0, "UTC") do
          reminder = build(:reminder, user: user,
                           fire_at: Time.new(2026, 3, 1, 12, 0, 0, "UTC"))

          expect(reminder.day_label).to eq("Mar 1")
        end
      end
    end

    context "when UTC date is ahead of the user's local date" do
      # 2 AM UTC on Feb 25 = 9 PM ET on Feb 24
      it "uses the user's timezone for 'today', not the UTC date" do
        travel_to Time.new(2026, 2, 25, 2, 0, 0, "UTC") do
          # fire_at in ET = 9 PM Feb 24 (same local day as now)
          reminder = build(:reminder, user: user,
                           fire_at: Time.new(2026, 2, 25, 2, 0, 0, "UTC"))

          expect(reminder.day_label).to eq("today")
        end
      end

      it "uses the user's timezone for 'tomorrow', not the UTC date" do
        travel_to Time.new(2026, 2, 25, 2, 0, 0, "UTC") do
          # fire_at in ET = 7 AM Feb 25 (next local day)
          reminder = build(:reminder, user: user,
                           fire_at: Time.new(2026, 2, 25, 12, 0, 0, "UTC"))

          expect(reminder.day_label).to eq("tomorrow")
        end
      end
    end
  end

  describe "defaults" do
    it "defaults to pending status" do
      reminder = build(:reminder)

      expect(reminder.status).to eq("pending")
    end
  end
end
