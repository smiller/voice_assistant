require "rails_helper"

RSpec.describe VoiceAlertsController, type: :request do
  let(:audio_bytes) { "\xFF\xFB\x90\x00".b }
  let(:token) { "abc123" }
  let(:cache_key) { "reminder_audio_#{token}" }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
  end

  describe "GET /voice_alerts/:id" do
    context "when token is not in cache" do
      it "returns 404" do
        get "/voice_alerts/#{token}"

        expect(response).to have_http_status(:not_found)
      end
    end

    context "when token is in cache" do
      before { cache_store.write(cache_key, audio_bytes) }

      it "returns the audio bytes with audio/mpeg content type and inline disposition" do
        get "/voice_alerts/#{token}"

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq("audio/mpeg")
        expect(response.body.b).to eq(audio_bytes)
        expect(response.headers["Content-Disposition"]).to include("inline")
      end

      it "deletes the token from cache after serving" do
        get "/voice_alerts/#{token}"

        expect(cache_store.read(cache_key)).to be_nil
      end
    end
  end
end
