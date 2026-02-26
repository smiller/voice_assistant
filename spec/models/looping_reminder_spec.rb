require "rails_helper"

RSpec.describe LoopingReminder do
  describe "associations" do
    it "belongs to a user" do
      loop = build(:looping_reminder)

      expect(loop.user).to be_a(User)
    end

    it "has many command aliases" do
      loop = create(:looping_reminder)
      create(:command_alias, looping_reminder: loop)

      expect(loop.command_aliases.count).to eq(1)
    end

    it "destroys dependent command aliases" do
      loop = create(:looping_reminder)
      create(:command_alias, looping_reminder: loop)

      expect { loop.destroy }.to change(CommandAlias, :count).by(-1)
    end
  end

  describe "validations" do
    it "is valid with all required attributes" do
      loop = build(:looping_reminder)

      expect(loop).to be_valid
    end

    it "is invalid without a user" do
      loop = build(:looping_reminder, user: nil)

      expect(loop).not_to be_valid
    end

    it "is invalid without a message" do
      loop = build(:looping_reminder, message: nil)

      expect(loop).not_to be_valid
    end

    it "is invalid without a stop_phrase" do
      loop = build(:looping_reminder, stop_phrase: nil)

      expect(loop).not_to be_valid
    end

    it "is invalid with interval_minutes less than 1" do
      loop = build(:looping_reminder, interval_minutes: 0)

      expect(loop).not_to be_valid
    end

    it "is valid with interval_minutes of 1" do
      loop = build(:looping_reminder, interval_minutes: 1)

      expect(loop).to be_valid
    end

    it "is invalid with a duplicate number for the same user" do
      user = create(:user)
      create(:looping_reminder, user: user, number: 1)
      duplicate = build(:looping_reminder, user: user, number: 1)

      expect(duplicate).not_to be_valid
    end

    it "allows the same number for different users" do
      create(:looping_reminder, number: 1)
      other = build(:looping_reminder, number: 1)

      expect(other).to be_valid
    end

    it "is invalid with a message longer than 500 characters" do
      loop = build(:looping_reminder, message: "a" * 501)

      expect(loop).not_to be_valid
    end

    it "is valid with a message of exactly 500 characters" do
      loop = build(:looping_reminder, message: "a" * 500)

      expect(loop).to be_valid
    end

    it "is invalid with a stop_phrase longer than 100 characters" do
      loop = build(:looping_reminder, stop_phrase: "a" * 101)

      expect(loop).not_to be_valid
    end

    it "is valid with a stop_phrase of exactly 100 characters" do
      loop = build(:looping_reminder, stop_phrase: "a" * 100)

      expect(loop).to be_valid
    end

    it "is invalid with interval_minutes greater than 1440" do
      loop = build(:looping_reminder, interval_minutes: 1441)

      expect(loop).not_to be_valid
    end

    it "is valid with interval_minutes of 1440" do
      loop = build(:looping_reminder, interval_minutes: 1440)

      expect(loop).to be_valid
    end
  end

  describe "#job_epoch" do
    it "is 0 for a new looping reminder" do
      loop = create(:looping_reminder)

      expect(loop.job_epoch).to eq(0)
    end
  end

  describe "#activate!" do
    it "sets active to true" do
      loop = create(:looping_reminder, active: false)

      loop.activate!

      expect(loop.reload.active).to be(true)
    end

    it "increments job_epoch by 1" do
      loop = create(:looping_reminder, active: false)

      loop.activate!

      expect(loop.reload.job_epoch).to eq(1)
    end

    it "increments job_epoch on each successive activation" do
      loop = create(:looping_reminder, active: false)
      loop.activate!
      loop.stop!

      loop.activate!

      expect(loop.reload.job_epoch).to eq(2)
    end
  end

  describe "#stop!" do
    it "sets active to false" do
      loop = create(:looping_reminder, active: true)

      loop.stop!

      expect(loop.reload.active).to be(false)
    end

    it "does not change job_epoch" do
      loop = create(:looping_reminder, active: true)
      original_epoch = loop.job_epoch

      loop.stop!

      expect(loop.reload.job_epoch).to eq(original_epoch)
    end
  end

  describe ".active_loops" do
    it "returns only active looping reminders" do
      active = create(:looping_reminder, active: true)
      create(:looping_reminder, active: false)

      expect(described_class.active_loops).to eq([ active ])
    end
  end

  describe ".next_number_for" do
    it "issues a SELECT FOR UPDATE to prevent concurrent duplicate numbers" do
      user = create(:user)
      sql_log = []
      subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
        sql_log << payload[:sql]
      end

      described_class.next_number_for(user)

      ActiveSupport::Notifications.unsubscribe(subscriber)
      expect(sql_log.any? { |sql| sql.include?("FOR UPDATE") }).to be(true)
    end

    it "returns 1 when user has no loops" do
      user = create(:user)

      expect(described_class.next_number_for(user)).to eq(1)
    end

    it "returns max + 1 when user has existing loops" do
      user = create(:user)
      create(:looping_reminder, user: user, number: 1)
      create(:looping_reminder, user: user, number: 2)

      expect(described_class.next_number_for(user)).to eq(3)
    end

    it "returns max + 1 based on highest number, not insertion order" do
      user = create(:user)
      create(:looping_reminder, user: user, number: 5)
      create(:looping_reminder, user: user, number: 2)

      expect(described_class.next_number_for(user)).to eq(6)
    end

    it "scopes number sequence per user" do
      user1 = create(:user)
      user2 = create(:user)
      create(:looping_reminder, user: user1, number: 5)

      expect(described_class.next_number_for(user2)).to eq(1)
    end
  end
end
