require "rails_helper"

RSpec.describe Api::V1::PendingInteractionsController, type: :request do
  let(:user) { create(:user) }
  let(:headers) { { "Authorization" => "Bearer #{user.api_token}" } }

  before { user }

  describe "GET /api/v1/pending_interaction" do
    context "without authentication" do
      it "returns 401" do
        get "/api/v1/pending_interaction"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with an invalid token" do
      it "returns 401" do
        get "/api/v1/pending_interaction",
          headers: { "Authorization" => "Bearer wrong_token" }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with a valid token and no pending interaction" do
      it "returns 204" do
        get "/api/v1/pending_interaction", headers: headers

        expect(response).to have_http_status(:no_content)
      end
    end

    context "with a valid token and an active pending interaction" do
      let!(:pending) do
        create(:pending_interaction,
               user: user,
               kind: "stop_phrase_replacement",
               context: { "interval_minutes" => 5, "message" => "have you done the dishes?" },
               expires_at: 10.minutes.from_now)
      end

      it "returns 200" do
        get "/api/v1/pending_interaction", headers: headers

        expect(response).to have_http_status(:ok)
      end

      it "returns JSON content type" do
        get "/api/v1/pending_interaction", headers: headers

        expect(response.content_type).to include("application/json")
      end

      it "includes kind, context, and expires_at" do
        get "/api/v1/pending_interaction", headers: headers

        data = JSON.parse(response.body)
        expect(data["kind"]).to eq("stop_phrase_replacement")
        expect(data["context"]).to eq({ "interval_minutes" => 5, "message" => "have you done the dishes?" })
        expect(data["expires_at"]).to eq(pending.expires_at.as_json)
      end

      it "does not return an expired interaction" do
        pending.update!(expires_at: 1.minute.ago)

        get "/api/v1/pending_interaction", headers: headers

        expect(response).to have_http_status(:no_content)
      end
    end

    context "with another user's pending interaction" do
      it "returns 204 for the authenticated user" do
        other_user = create(:user)
        create(:pending_interaction, user: other_user)

        get "/api/v1/pending_interaction", headers: headers

        expect(response).to have_http_status(:no_content)
      end
    end
  end
end
