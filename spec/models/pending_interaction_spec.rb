require "rails_helper"

RSpec.describe PendingInteraction do
  describe "INTERACTION_TTL" do
    it "is 5 minutes" do
      expect(described_class::INTERACTION_TTL).to eq(5.minutes)
    end
  end

  describe "associations" do
    it "belongs to a user" do
      pi = build(:pending_interaction)

      expect(pi.user).to be_a(User)
    end
  end

  describe "validations" do
    it "is valid with all required attributes" do
      pi = build(:pending_interaction)

      expect(pi).to be_valid
    end

    it "is invalid without a kind" do
      pi = build(:pending_interaction, kind: nil)

      expect(pi).not_to be_valid
    end

    it "is invalid with an unrecognized kind" do
      pi = build(:pending_interaction, kind: "unknown_kind")

      expect(pi).not_to be_valid
    end

    it "is valid with stop_phrase_replacement kind" do
      pi = build(:pending_interaction, kind: "stop_phrase_replacement")

      expect(pi).to be_valid
    end

    it "is valid with alias_phrase_replacement kind" do
      pi = build(:pending_interaction, kind: "alias_phrase_replacement")

      expect(pi).to be_valid
    end

    it "is invalid without expires_at" do
      pi = build(:pending_interaction, expires_at: nil)

      expect(pi).not_to be_valid
    end
  end

  describe ".active scope" do
    it "returns interactions that have not expired" do
      active = create(:pending_interaction, expires_at: 1.minute.from_now)

      expect(described_class.active).to include(active)
    end

    it "excludes expired interactions" do
      create(:pending_interaction, expires_at: 1.minute.ago)

      expect(described_class.active).to be_empty
    end
  end

  describe ".for" do
    it "returns the earliest active interaction for the user" do
      user = create(:user)
      # Create newer first (lower id) so id order != created_at order
      newer = create(:pending_interaction, user: user, expires_at: 10.minutes.from_now)
      older = create(:pending_interaction, user: user, created_at: 5.minutes.ago, expires_at: 10.minutes.from_now)

      result = described_class.for(user)
      expect(result).to eq(older)
      expect(result).not_to eq(newer)
    end

    it "returns nil when user has no active interactions" do
      user = create(:user)

      expect(described_class.for(user)).to be_nil
    end

    it "returns nil when all interactions are expired" do
      user = create(:user)
      create(:pending_interaction, user: user, expires_at: 1.minute.ago)

      expect(described_class.for(user)).to be_nil
    end

    it "does not return another user's interaction" do
      user1 = create(:user)
      user2 = create(:user)
      create(:pending_interaction, user: user1)

      expect(described_class.for(user2)).to be_nil
    end
  end
end
