require "rails_helper"

RSpec.describe "Reminder delivery", type: :request do
  let(:user) { create(:user, elevenlabs_voice_id: "voice123") }
  let(:reminder) { create(:reminder, user: user, message: "take medication", fire_at: 1.minute.from_now) }
  let(:audio_bytes) { "\xFF\xFB\x90\x00".b }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
    allow(ElevenLabsClient).to receive(:new).and_return(
      instance_double(ElevenLabsClient, synthesize: audio_bytes)
    )
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(SecureRandom).to receive(:hex).and_return("testtoken")
    post "/session", params: { email: user.email, password: "s3cr3tpassword" }
  end

  it "job fires and audio is retrievable via GET /voice_alerts/:token" do
    ReminderJob.perform_now(reminder.id)

    get "/voice_alerts/testtoken"

    expect(response).to have_http_status(:ok)
    expect(response.content_type).to eq("audio/mpeg")
    expect(response.body.b).to eq(audio_bytes)
  end

  it "token is consumed after the first fetch" do
    ReminderJob.perform_now(reminder.id)

    get "/voice_alerts/testtoken"
    get "/voice_alerts/testtoken"

    expect(response).to have_http_status(:not_found)
  end
end
