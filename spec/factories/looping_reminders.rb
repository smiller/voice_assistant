FactoryBot.define do
  factory :looping_reminder do
    association :user
    sequence(:number) { |n| n }
    interval_minutes { 5 }
    message { "have you done the dishes?" }
    sequence(:stop_phrase) { |n| "stop phrase #{n}" }
    active { false }

    trait :active do
      active { true }
    end
  end
end
