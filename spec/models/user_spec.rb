require "rails_helper"

RSpec.describe User do
  describe "validations" do
    it "is valid with email and password" do
      user = build(:user)

      expect(user).to be_valid
    end

    it "is invalid without email" do
      user = build(:user, email: nil)

      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "is invalid without password" do
      user = build(:user, password: nil)

      expect(user).not_to be_valid
      expect(user.errors[:password]).to be_present
    end

    it "is invalid with a duplicate email" do
      create(:user, email: "taken@example.com")
      user = build(:user, email: "taken@example.com")

      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end

    it "is invalid when email differs only by case" do
      create(:user, email: "taken@example.com")
      user = build(:user, email: "TAKEN@EXAMPLE.COM")

      expect(user).not_to be_valid
    end

    it "is invalid with a malformed email" do
      user = build(:user, email: "not-an-email")

      expect(user).not_to be_valid
      expect(user.errors[:email]).to be_present
    end
  end

  describe "optional fields" do
    it "is valid without elevenlabs_voice_id, lat, lng, or timezone" do
      user = build(:user, elevenlabs_voice_id: nil, lat: nil, lng: nil, timezone: nil)

      expect(user).to be_valid
    end
  end

  describe "#authenticate" do
    let(:user) { create(:user, password: "correct_horse") }

    it "authenticates with the correct password" do
      expect(user.authenticate("correct_horse")).to eq(user)
    end

    it "does not authenticate with an incorrect password" do
      expect(user.authenticate("wrong_password")).to be(false)
    end

    it "does not store the password in plain text" do
      expect(user.password_digest).not_to eq("correct_horse")
    end
  end
end
