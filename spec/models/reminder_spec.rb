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

  describe "#next_in_list" do
    let(:user) { create(:user, timezone: "America/New_York") }

    context "for a reminder" do
      it "returns nil when no other reminders are pending" do
        reminder = create(:reminder, user: user, fire_at: 2.hours.from_now)

        expect(reminder.next_in_list).to be_nil
      end

      it "returns nil when all other reminders fire before it" do
        earlier = create(:reminder, user: user, fire_at: 1.hour.from_now)
        later   = create(:reminder, user: user, fire_at: 3.hours.from_now)

        expect(later.next_in_list).to be_nil
      end

      it "returns the first reminder that fires after it" do
        earlier = create(:reminder, user: user, fire_at: 1.hour.from_now)
        later   = create(:reminder, user: user, fire_at: 3.hours.from_now)

        expect(earlier.next_in_list).to eq(later)
      end

      it "does not return reminders of a different kind" do
        reminder = create(:reminder, user: user, fire_at: 1.hour.from_now)
        _timer   = create(:reminder, :timer, user: user, fire_at: 2.hours.from_now)

        expect(reminder.next_in_list).to be_nil
      end

      it "does not return cancelled reminders" do
        reminder   = create(:reminder, user: user, fire_at: 1.hour.from_now)
        _cancelled = create(:reminder, user: user, fire_at: 2.hours.from_now, status: "cancelled")

        expect(reminder.next_in_list).to be_nil
      end

      it "uses absolute fire_at not time-of-day — 11pm today sees 7am tomorrow as next" do
        travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do  # midnight ET
          eleven_pm = create(:reminder, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 23, 0, 0) })
          seven_am  = create(:reminder, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 24, 7, 0, 0) })

          expect(eleven_pm.next_in_list).to eq(seven_am)
        end
      end

      it "returns the reminder with the earliest fire_at among those that come after it" do
        first  = create(:reminder, user: user, fire_at: 1.hour.from_now)
        # Create in reverse fire_at order so id order differs from fire_at order
        fourth = create(:reminder, user: user, fire_at: 4.hours.from_now)
        second = create(:reminder, user: user, fire_at: 2.hours.from_now)

        expect(first.next_in_list).to eq(second)
      end
    end

    context "for a daily_reminder" do
      it "returns nil when no other daily reminders are pending" do
        travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do
          daily = create(:reminder, :daily, user: user,
                         fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 23, 0, 0) })

          expect(daily.next_in_list).to be_nil
        end
      end

      it "returns the daily reminder with the next later time-of-day" do
        travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do
          seven_am  = create(:reminder, :daily, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 7, 0, 0) })
          eleven_pm = create(:reminder, :daily, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 23, 0, 0) })

          expect(seven_am.next_in_list).to eq(eleven_pm)
        end
      end

      it "returns nil when all other daily reminders have an earlier time-of-day" do
        travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do
          seven_am  = create(:reminder, :daily, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 7, 0, 0) })
          eleven_pm = create(:reminder, :daily, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 23, 0, 0) })

          expect(eleven_pm.next_in_list).to be_nil
        end
      end

      it "uses time-of-day not absolute fire_at — 11pm tonight sorts before 7am tomorrow" do
        # 11 PM tonight has earlier fire_at than 7 AM tomorrow, but later time-of-day
        travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do  # midnight ET
          eleven_pm = create(:reminder, :daily, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 23, 0, 0) })
          seven_am  = create(:reminder, :daily, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 24, 7, 0, 0) })

          expect(seven_am.next_in_list).to eq(eleven_pm)
        end
      end

      it "does not return cancelled daily reminders" do
        travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do  # midnight ET
          seven_am   = create(:reminder, :daily, user: user,
                              fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 7, 0, 0) })
          _cancelled = create(:reminder, :daily, user: user, status: "cancelled",
                              fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 9, 0, 0) })

          expect(seven_am.next_in_list).to be_nil
        end
      end

      it "does not return past daily reminders even if they have a later time-of-day" do
        travel_to Time.new(2026, 2, 23, 14, 0, 0, "UTC") do  # 9 AM ET
          ten_am       = create(:reminder, :daily, user: user,
                                fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 10, 0, 0) })
          _past_late   = create(:reminder, :daily, user: user,
                                fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 22, 23, 0, 0) })

          expect(ten_am.next_in_list).to be_nil
        end
      end

      it "finds the first time-of-day after self when siblings are not in time-of-day order in the database" do
        travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do  # midnight ET
          nine_am   = create(:reminder, :daily, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 9, 0, 0) })
          # Create eleven_pm first so it has a lower id than two_pm (earlier DB order)
          eleven_pm = create(:reminder, :daily, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 23, 0, 0) })
          two_pm    = create(:reminder, :daily, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 14, 0, 0) })

          # Without sort: eleven_pm (23:00) found first since id < two_pm's id, and 23:00 > 9:00
          # With sort: two_pm (14:00) is found first as the closest time after 9:00
          expect(nine_am.next_in_list).to eq(two_pm)
        end
      end

      it "uses time-of-day not absolute fire_at — 2pm tomorrow is next after 9am when 11pm fires sooner" do
        # 11 PM tonight fires sooner (earlier fire_at), but 2 PM tomorrow has an earlier time-of-day
        travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do  # midnight ET
          nine_am   = create(:reminder, :daily, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 9, 0, 0) })
          eleven_pm = create(:reminder, :daily, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 23, 0, 0) })
          two_pm    = create(:reminder, :daily, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 24, 14, 0, 0) })

          # sort_by fire_at: eleven_pm (tonight), two_pm (tomorrow) → finds eleven_pm first (WRONG)
          # sort_by time_of_day: two_pm (14:00), eleven_pm (23:00) → finds two_pm first (CORRECT)
          expect(nine_am.next_in_list).to eq(two_pm)
        end
      end
    end

    context "for a timer" do
      it "returns nil when no other timers are pending" do
        timer = create(:reminder, :timer, user: user, fire_at: 2.hours.from_now)

        expect(timer.next_in_list).to be_nil
      end

      it "returns the timer that fires next after it" do
        sooner = create(:reminder, :timer, user: user, fire_at: 1.hour.from_now)
        later  = create(:reminder, :timer, user: user, fire_at: 3.hours.from_now)

        expect(sooner.next_in_list).to eq(later)
      end

      it "does not return reminders of a different kind" do
        timer    = create(:reminder, :timer, user: user, fire_at: 1.hour.from_now)
        _regular = create(:reminder, user: user, fire_at: 2.hours.from_now)

        expect(timer.next_in_list).to be_nil
      end
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
