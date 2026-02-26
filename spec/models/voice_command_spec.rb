require "rails_helper"

RSpec.describe VoiceCommand do
  describe "associations" do
    it "belongs to a user" do
      voice_command = build(:voice_command)

      expect(voice_command.user).to be_a(User)
    end
  end

  describe "validations" do
    it "is valid with user, transcript, intent, and status" do
      voice_command = build(:voice_command)

      expect(voice_command).to be_valid
    end

    it "is invalid without a user" do
      voice_command = build(:voice_command, user: nil)

      expect(voice_command).not_to be_valid
      expect(voice_command.errors[:user]).to be_present
    end

    it "is invalid without a transcript" do
      voice_command = build(:voice_command, transcript: nil)

      expect(voice_command).not_to be_valid
      expect(voice_command.errors[:transcript]).to be_present
    end

    it "is invalid without a status" do
      voice_command = build(:voice_command, status: nil)

      expect(voice_command).not_to be_valid
      expect(voice_command.errors[:status]).to be_present
    end
  end

  describe "enums" do
    it "defines intent values" do
      expect(VoiceCommand.intents.keys).to match_array(%w[time_check sunset timer reminder daily_reminder create_loop run_loop stop_loop alias_loop complete_pending give_up unknown])
    end

    it "defines status values" do
      expect(VoiceCommand.statuses.keys).to match_array(%w[received processed])
    end
  end
end
