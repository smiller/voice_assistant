require "rails_helper"

RSpec.describe Api::V1::TextCommandsController, type: :request do
  let(:user) { create(:user, api_token: "valid_token") }
  let(:audio_bytes) { "\xFF\xFB\x90\x00response audio" }
  let(:responder) { instance_double(CommandResponder, respond: audio_bytes) }

  before do
    allow(CommandResponder).to receive(:new).and_return(responder)
  end

  describe "POST /api/v1/text_commands" do
    context "without authentication" do
      it "returns 401" do
        post "/api/v1/text_commands", params: { transcript: "what time is it" }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with an invalid token" do
      it "returns 401" do
        post "/api/v1/text_commands",
          params: { transcript: "what time is it" },
          headers: { "Authorization" => "Bearer wrong_token" }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with a valid token" do
      let(:headers) { { "Authorization" => "Bearer valid_token" } }

      before { user }

      it "returns audio/mpeg with synthesized bytes inline" do
        post "/api/v1/text_commands",
          params: { transcript: "what time is it" },
          headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq("audio/mpeg")
        expect(response.body).to eq(audio_bytes)
        expect(response.headers["Content-Disposition"]).to eq("inline")
      end

      it "parses the transcript and calls respond with the command" do
        post "/api/v1/text_commands",
          params: { transcript: "what time is it" },
          headers: headers

        expect(responder).to have_received(:respond)
          .with(command: { intent: :time_check, params: {} }, user: user)
      end

      it "returns 400 when transcript param is missing" do
        post "/api/v1/text_commands", headers: headers

        expect(response).to have_http_status(:bad_request)
      end

      it "returns 400 when transcript is blank" do
        post "/api/v1/text_commands",
          params: { transcript: "" },
          headers: headers

        expect(response).to have_http_status(:bad_request)
      end
    end
  end
end
