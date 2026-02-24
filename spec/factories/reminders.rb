FactoryBot.define do
  factory :reminder do
    association :user
    kind { "reminder" }
    message { "take medication" }
    fire_at { 1.hour.from_now }
    recurs_daily { false }
    status { "pending" }

    trait :timer do
      kind { "timer" }
      message { "Timer finished after 5 minutes" }
    end

    trait :daily do
      kind { "daily_reminder" }
      recurs_daily { true }
    end
  end
end
