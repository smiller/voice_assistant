FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "s3cr3tpassword" }
    lat { nil }
    lng { nil }

    trait :voiced do
      elevenlabs_voice_id { "voice123" }
      timezone { "America/New_York" }
    end

    trait :located do
      lat { 40.7128 }
      lng { -74.0060 }
    end
  end
end
