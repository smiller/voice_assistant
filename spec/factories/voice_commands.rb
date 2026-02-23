FactoryBot.define do
  factory :voice_command do
    association :user
    transcript { "what time is it" }
    intent { "time_check" }
    params { {} }
    status { "received" }
  end
end
