FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "s3cr3tpassword" }
    elevenlabs_voice_id { nil }
    lat { nil }
    lng { nil }
    timezone { nil }
  end
end
