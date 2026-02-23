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
