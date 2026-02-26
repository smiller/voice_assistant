require "rails_helper"

RSpec.describe CommandAlias do
  describe "associations" do
    it "belongs to a looping reminder" do
      al = build(:command_alias)

      expect(al.looping_reminder).to be_a(LoopingReminder)
    end

    it "belongs to a user" do
      al = build(:command_alias)

      expect(al.user).to be_a(User)
    end
  end

  describe "validations" do
    it "is valid with all required attributes" do
      al = build(:command_alias)

      expect(al).to be_valid
    end

    it "is invalid without a phrase" do
      al = build(:command_alias, phrase: nil)

      expect(al).not_to be_valid
    end

    it "is invalid with a duplicate phrase for the same user (case-insensitive)" do
      user = create(:user)
      loop = create(:looping_reminder, user: user)
      create(:command_alias, user: user, looping_reminder: loop, phrase: "do the dishes")
      duplicate = build(:command_alias, user: user, looping_reminder: loop, phrase: "Do The Dishes")

      expect(duplicate).not_to be_valid
    end

    it "allows the same phrase for different users" do
      user1 = create(:user)
      user2 = create(:user)
      loop1 = create(:looping_reminder, user: user1)
      loop2 = create(:looping_reminder, user: user2)
      create(:command_alias, user: user1, looping_reminder: loop1, phrase: "do the dishes")
      other = build(:command_alias, user: user2, looping_reminder: loop2, phrase: "do the dishes")

      expect(other).to be_valid
    end
  end
end
