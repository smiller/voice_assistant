FactoryBot.define do
  factory :reminder do
    association :user
    kind { "reminder" }
    message { "take medication" }
    fire_at { 1.hour.from_now }
    recurs_daily { false }
    status { "pending" }
  end
end
