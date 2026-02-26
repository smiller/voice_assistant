require "rails_helper"

RSpec.describe Api::V1::LoopingRemindersController, type: :request do
  let(:user) { create(:user, api_token: "valid_token") }
  let(:headers) { { "Authorization" => "Bearer valid_token" } }

  before { user }

  describe "GET /api/v1/looping_reminders" do
    context "without authentication" do
      it "returns 401" do
        get "/api/v1/looping_reminders"

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with an invalid token" do
      it "returns 401" do
        get "/api/v1/looping_reminders",
          headers: { "Authorization" => "Bearer wrong_token" }

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with a valid token" do
      it "returns 200 with JSON content type" do
        get "/api/v1/looping_reminders", headers: headers

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/json")
      end

      it "returns an empty array when user has no looping reminders" do
        get "/api/v1/looping_reminders", headers: headers

        expect(JSON.parse(response.body)).to eq([])
      end

      it "returns loops ordered by number with all required fields" do
        reminder = create(:looping_reminder, user: user, number: 1, active: true)

        get "/api/v1/looping_reminders", headers: headers

        data = JSON.parse(response.body)
        expect(data.length).to eq(1)
        entry = data.first
        expect(entry["id"]).to eq(reminder.id)
        expect(entry["number"]).to eq(1)
        expect(entry["message"]).to eq(reminder.message)
        expect(entry["stop_phrase"]).to eq(reminder.stop_phrase)
        expect(entry["interval_minutes"]).to eq(reminder.interval_minutes)
        expect(entry["active"]).to be(true)
        expect(entry["aliases"]).to eq([])
      end

      it "includes command aliases in the aliases array" do
        reminder = create(:looping_reminder, user: user, number: 1)
        create(:command_alias, user: user, looping_reminder: reminder, phrase: "do the dishes")

        get "/api/v1/looping_reminders", headers: headers

        data = JSON.parse(response.body)
        expect(data.first["aliases"]).to eq([ "do the dishes" ])
      end

      it "returns loops in ascending number order" do
        create(:looping_reminder, user: user, number: 3)
        create(:looping_reminder, user: user, number: 1)

        get "/api/v1/looping_reminders", headers: headers

        data = JSON.parse(response.body)
        expect(data.map { |d| d["number"] }).to eq([ 1, 3 ])
      end

      it "does not return another user's looping reminders" do
        other_user = create(:user, api_token: "other_token")
        create(:looping_reminder, user: other_user, number: 1)

        get "/api/v1/looping_reminders", headers: headers

        expect(JSON.parse(response.body)).to eq([])
      end
    end
  end
end
