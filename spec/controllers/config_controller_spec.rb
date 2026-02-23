require "rails_helper"

RSpec.describe ConfigController, type: :request do
  let(:user) { create(:user, elevenlabs_voice_id: "voice123") }

  def log_in
    post "/session", params: { email: user.email, password: "s3cr3tpassword" }
  end

  describe "GET /config" do
    context "when not authenticated" do
      it "redirects to login" do
        get "/config"

        expect(response).to redirect_to(login_path)
      end
    end

    context "when authenticated" do
      before do
        log_in
        ENV["DEEPGRAM_API_KEY"] = "test_dg_key"
      end

      after { ENV.delete("DEEPGRAM_API_KEY") }

      it "returns JSON with deepgram_key and voice_id" do
        get "/config"

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")
        body = JSON.parse(response.body)
        expect(body["deepgram_key"]).to eq("test_dg_key")
        expect(body["voice_id"]).to eq("voice123")
      end
    end
  end
end
