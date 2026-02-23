require "rails_helper"

RSpec.describe SettingsController, type: :request do
  let(:user) { create(:user) }

  def log_in
    post "/session", params: { email: user.email, password: "s3cr3tpassword" }
  end

  describe "GET /settings/edit" do
    context "when not authenticated" do
      it "redirects to login" do
        get "/settings/edit"

        expect(response).to redirect_to(login_path)
      end
    end

    context "when authenticated" do
      before { log_in }

      it "returns 200" do
        get "/settings/edit"

        expect(response).to have_http_status(:ok)
      end
    end
  end

  describe "PATCH /settings" do
    context "when not authenticated" do
      it "redirects to login" do
        patch "/settings", params: { user: { elevenlabs_voice_id: "newvoice" } }

        expect(response).to redirect_to(login_path)
      end
    end

    context "when authenticated" do
      before { log_in }

      it "updates the user's settings and redirects to root" do
        patch "/settings", params: {
          user: { elevenlabs_voice_id: "newvoice", lat: "51.5", lng: "-0.1", timezone: "Europe/London" }
        }

        expect(response).to redirect_to(root_path)
        user.reload
        expect(user.elevenlabs_voice_id).to eq("newvoice")
        expect(user.lat).to eq(51.5)
        expect(user.lng).to eq(-0.1)
        expect(user.timezone).to eq("Europe/London")
      end

      it "re-renders edit with 422 when update fails" do
        allow_any_instance_of(User).to receive(:update).and_return(false)

        patch "/settings", params: { user: { elevenlabs_voice_id: "newvoice" } }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end
end
