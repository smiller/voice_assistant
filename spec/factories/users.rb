FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "s3cr3tpassword" }
    lat { nil }
    lng { nil }
  end
end
