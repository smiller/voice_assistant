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
      before { log_in }

      it "returns JSON with voice_id" do
        get "/config"

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")
        body = JSON.parse(response.body)
        expect(body["voice_id"]).to eq("voice123")
      end

      it "does not expose deepgram_key" do
        get "/config"

        body = JSON.parse(response.body)
        expect(body).not_to have_key("deepgram_key")
      end
    end
  end
end
