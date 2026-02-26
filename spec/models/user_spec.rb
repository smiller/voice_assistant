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

  describe "lat/lng range validation" do
    it "is valid with nil lat and lng" do
      user = build(:user, lat: nil, lng: nil)

      expect(user).to be_valid
    end

    it "is invalid with lat below -90" do
      user = build(:user, lat: -91)

      expect(user).not_to be_valid
      expect(user.errors[:lat]).to be_present
    end

    it "is invalid with lat above 90" do
      user = build(:user, lat: 91)

      expect(user).not_to be_valid
      expect(user.errors[:lat]).to be_present
    end

    it "is invalid with lng below -180" do
      user = build(:user, lng: -181)

      expect(user).not_to be_valid
      expect(user.errors[:lng]).to be_present
    end

    it "is invalid with lng above 180" do
      user = build(:user, lng: 181)

      expect(user).not_to be_valid
      expect(user.errors[:lng]).to be_present
    end

    it "is valid with boundary values lat: 90, lng: 180" do
      user = build(:user, lat: 90, lng: 180)

      expect(user).to be_valid
    end
  end

  describe "defaults" do
    around do |example|
      original = ENV.fetch("ELEVENLABS_VOICE_ID", nil)
      ENV["ELEVENLABS_VOICE_ID"] = "default_voice"
      example.run
      ENV["ELEVENLABS_VOICE_ID"] = original
    end

    it "defaults elevenlabs_voice_id to the ELEVENLABS_VOICE_ID env var" do
      user = build(:user)

      expect(user.elevenlabs_voice_id).to eq("default_voice")
    end

    it "does not override an explicitly set elevenlabs_voice_id" do
      user = build(:user, elevenlabs_voice_id: "custom_voice")

      expect(user.elevenlabs_voice_id).to eq("custom_voice")
    end

    it "defaults timezone to Eastern Time (US & Canada)" do
      user = build(:user)

      expect(user.timezone).to eq("Eastern Time (US & Canada)")
    end

    it "does not override an explicitly set timezone" do
      user = build(:user, timezone: "Pacific Time (US & Canada)")

      expect(user.timezone).to eq("Pacific Time (US & Canada)")
    end
  end

  describe "#phrase_taken?" do
    let(:user) { create(:user) }

    it "returns true when stop phrase matches a looping reminder case-insensitively" do
      create(:looping_reminder, user: user, stop_phrase: "doing the dishes")

      expect(user.phrase_taken?("Doing The Dishes")).to be(true)
    end

    it "returns true when phrase matches a command alias case-insensitively" do
      other = create(:looping_reminder, user: user)
      create(:command_alias, user: user, looping_reminder: other, phrase: "do the thing")

      expect(user.phrase_taken?("DO THE THING")).to be(true)
    end

    it "returns false when neither association has a match" do
      expect(user.phrase_taken?("something unique")).to be(false)
    end

    it "returns false when user has looping reminders with a different stop phrase" do
      create(:looping_reminder, user: user, stop_phrase: "not a match")

      expect(user.phrase_taken?("doing the dishes")).to be(false)
    end

    it "returns false when user has aliases with a different phrase" do
      other = create(:looping_reminder, user: user)
      create(:command_alias, user: user, looping_reminder: other, phrase: "not a match")

      expect(user.phrase_taken?("do the thing")).to be(false)
    end

    it "does not match another user's phrases" do
      other_user = create(:user)
      create(:looping_reminder, user: other_user, stop_phrase: "their phrase")

      expect(user.phrase_taken?("their phrase")).to be(false)
    end
  end

  describe "#api_token" do
    it "is generated automatically on create" do
      user = create(:user)

      expect(user.api_token).to be_present
    end

    it "generates a token of at least 24 characters" do
      user = create(:user)

      expect(user.api_token.length).to be >= 24
    end

    it "stores a SHA-256 digest — not the raw token — in api_token_digest" do
      user = create(:user)
      raw = user.api_token
      expected_digest = OpenSSL::Digest::SHA256.hexdigest(raw)

      expect(user.api_token_digest).to eq(expected_digest)
      expect(user.api_token_digest).not_to eq(raw)
    end
  end

  describe "#authenticate_api_token" do
    it "returns true with the correct token" do
      user = create(:user)
      token = user.api_token

      expect(user.authenticate_api_token(token)).to be(true)
    end

    it "returns false with an incorrect token" do
      user = create(:user)

      expect(user.authenticate_api_token("wrong_token")).to be(false)
    end

    it "returns false when given the digest string instead of the raw token" do
      user = create(:user)

      expect(user.authenticate_api_token(user.api_token_digest)).to be(false)
    end

    it "returns false when api_token_digest is nil" do
      user = create(:user)
      user.update_column(:api_token_digest, nil)

      expect(user.authenticate_api_token("any_token")).to be(false)
    end
  end

  describe "#regenerate_api_token" do
    it "produces a new raw token different from the original" do
      user = create(:user)
      old_token = user.api_token

      user.regenerate_api_token

      expect(user.api_token).not_to eq(old_token)
    end

    it "generates a new token of at least 24 characters" do
      user = create(:user)

      user.regenerate_api_token

      expect(user.api_token.length).to be >= 24
    end

    it "makes the new token authenticate successfully" do
      user = create(:user)
      user.regenerate_api_token
      new_token = user.api_token

      expect(user.authenticate_api_token(new_token)).to be(true)
    end

    it "invalidates the old token" do
      user = create(:user)
      old_token = user.api_token

      user.regenerate_api_token

      expect(user.authenticate_api_token(old_token)).to be(false)
    end

    it "persists the new digest to the database" do
      user = create(:user)

      user.regenerate_api_token

      persisted_digest = user.reload.api_token_digest
      expect(user.authenticate_api_token(user.api_token)).to be(true)
      expect(OpenSSL::Digest::SHA256.hexdigest(user.api_token)).to eq(persisted_digest)
    end
  end

  describe ".find_by_api_token" do
    it "returns the matching user for a valid token" do
      user = create(:user)
      token = user.api_token

      expect(described_class.find_by_api_token(token)).to eq(user)
    end

    it "returns nil when no user has that token" do
      create(:user)

      expect(described_class.find_by_api_token("nonexistent_token")).to be_nil
    end

    it "returns nil when given the digest string instead of the raw token" do
      user = create(:user)

      expect(described_class.find_by_api_token(user.api_token_digest)).to be_nil
    end

    it "does not return another user" do
      user1 = create(:user)
      create(:user)
      token = user1.api_token

      expect(described_class.find_by_api_token(token)).to eq(user1)
    end
  end

  describe ".digest_api_token" do
    it "returns a 64-character hex SHA-256 digest" do
      digest = described_class.digest_api_token("any_token")

      expect(digest).to match(/\A[0-9a-f]{64}\z/)
    end

    it "produces the same digest for the same input" do
      expect(described_class.digest_api_token("abc")).to eq(described_class.digest_api_token("abc"))
    end

    it "produces different digests for different inputs" do
      expect(described_class.digest_api_token("abc")).not_to eq(described_class.digest_api_token("xyz"))
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
