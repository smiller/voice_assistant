require "rails_helper"

RSpec.describe SessionsController, type: :request do
  let(:user) { create(:user, password: "s3cr3tpassword") }

  describe "POST /session" do
    context "with valid credentials" do
      it "sets the session and redirects to root" do
        post "/session", params: { email: user.email, password: "s3cr3tpassword" }

        expect(response).to redirect_to(root_path)
        expect(request.session[:user_id]).to eq(user.id)
      end

      it "saves lat/lng to the user when they are blank and params are provided" do
        post "/session", params: { email: user.email, password: "s3cr3tpassword",
                                   lat: "40.7128", lng: "-74.0060" }

        expect(user.reload.lat).to eq(BigDecimal("40.7128"))
        expect(user.reload.lng).to eq(BigDecimal("-74.0060"))
      end

      it "does not overwrite existing lat/lng" do
        user.update!(lat: 1.0, lng: 2.0)

        post "/session", params: { email: user.email, password: "s3cr3tpassword",
                                   lat: "40.7128", lng: "-74.0060" }

        expect(user.reload.lat).to eq(BigDecimal("1.0"))
        expect(user.reload.lng).to eq(BigDecimal("2.0"))
      end

      it "ignores blank lat/lng params" do
        post "/session", params: { email: user.email, password: "s3cr3tpassword",
                                   lat: "", lng: "" }

        expect(user.reload.lat).to be_nil
        expect(user.reload.lng).to be_nil
      end

      it "does not save when lat is blank but lng is present" do
        post "/session", params: { email: user.email, password: "s3cr3tpassword",
                                   lat: "", lng: "-74.0060" }

        expect(user.reload.lng).to be_nil
      end

      it "does not save when lng is blank but lat is present" do
        post "/session", params: { email: user.email, password: "s3cr3tpassword",
                                   lat: "40.7128", lng: "" }

        expect(user.reload.lat).to be_nil
      end
    end

    context "with an incorrect password" do
      it "renders the login form with unprocessable_content" do
        post "/session", params: { email: user.email, password: "wrong" }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end

    context "with a non-existent email" do
      it "renders the login form with unprocessable_content" do
        post "/session", params: { email: "nobody@example.com", password: "any" }

        expect(response).to have_http_status(:unprocessable_content)
      end
    end
  end

  describe "DELETE /session" do
    before do
      post "/session", params: { email: user.email, password: "s3cr3tpassword" }
    end

    it "clears the session and redirects to login" do
      delete "/session"

      expect(response).to redirect_to(login_path)
      expect(request.session[:user_id]).to be_nil
    end
  end
end
