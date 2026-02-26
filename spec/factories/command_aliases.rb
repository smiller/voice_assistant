FactoryBot.define do
  factory :command_alias do
    association :looping_reminder
    association :user
    sequence(:phrase) { |n| "alias phrase #{n}" }
  end
end
