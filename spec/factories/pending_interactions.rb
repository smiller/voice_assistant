FactoryBot.define do
  factory :pending_interaction do
    association :user
    kind { "stop_phrase_replacement" }
    context { { "looping_reminder_attrs" => { "interval_minutes" => 5, "message" => "have you done the dishes?", "stop_phrase" => "doing the dishes" } } }
    expires_at { 5.minutes.from_now }
  end
end
