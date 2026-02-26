require "rails_helper"

RSpec.describe VoiceCommandsController, type: :request do
  let(:user) { create(:user) }
  let(:audio_data) { ("\xFF\xFB\x90\x00" + "x" * 1.kilobyte).b }
  let(:audio_file) { Rack::Test::UploadedFile.new(StringIO.new(audio_data), "audio/webm", original_filename: "recording.webm") }
  let(:audio_bytes) { "\xFF\xFB\x90\x00response audio" }

  def log_in
    post "/session", params: { email: user.email, password: "s3cr3tpassword" }
  end

  describe "GET /voice_commands" do
    context "when not authenticated" do
      it "redirects to login" do
        get "/voice_commands"

        expect(response).to redirect_to(login_path)
      end
    end

    context "when authenticated" do
      before { log_in }

      it "returns 200" do
        get "/voice_commands"

        expect(response).to have_http_status(:ok)
      end

      it "renders pending timers ordered by fire_at" do
        later  = create(:reminder, :timer, user: user, fire_at: 2.hours.from_now)
        sooner = create(:reminder, :timer, user: user, fire_at: 1.hour.from_now)

        get "/voice_commands"

        expect(response.body.index("reminder_#{sooner.id}"))
          .to be < response.body.index("reminder_#{later.id}")
      end

      it "renders pending reminders ordered by fire_at" do
        later  = create(:reminder, user: user, fire_at: 2.hours.from_now)
        sooner = create(:reminder, user: user, fire_at: 1.hour.from_now)

        get "/voice_commands"

        expect(response.body.index("reminder_#{sooner.id}"))
          .to be < response.body.index("reminder_#{later.id}")
      end

      it "renders pending daily_reminders ordered by time of day in the user's timezone, not absolute fire_at" do
        # 10 PM ET: 11 PM fires tonight (earlier fire_at), 7 AM fires tomorrow (later fire_at)
        travel_to Time.new(2026, 2, 24, 3, 0, 0, "UTC") do  # 10:00 PM ET
          eleven_pm = create(:reminder, :daily, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 24, 23, 0, 0) })
          seven_am  = create(:reminder, :daily, user: user,
                             fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 25, 7, 0, 0) })

          get "/voice_commands"

          expect(response.body.index("reminder_#{seven_am.id}"))
            .to be < response.body.index("reminder_#{eleven_pm.id}")
        end
      end

      it "renders timers exactly once (in the timers section, not reminders)" do
        timer = create(:reminder, :timer, user: user)

        get "/voice_commands"

        expect(response.body.scan("reminder_#{timer.id}").length).to eq(1)
      end

      it "renders reminders exactly once (in the reminders section, not timers)" do
        reminder = create(:reminder, user: user)

        get "/voice_commands"

        expect(response.body.scan("reminder_#{reminder.id}").length).to eq(1)
      end

      it "renders daily reminders exactly once (in the daily_reminders section, not reminders)" do
        daily = create(:reminder, :daily, user: user)

        get "/voice_commands"

        expect(response.body.scan("reminder_#{daily.id}").length).to eq(1)
      end

      it "does not render delivered reminders" do
        delivered = create(:reminder, user: user, status: "delivered")

        get "/voice_commands"

        expect(response.body).not_to include("reminder_#{delivered.id}")
      end

      it "does not render another user's reminders" do
        other = create(:reminder)

        get "/voice_commands"

        expect(response.body).not_to include("reminder_#{other.id}")
      end

      it "does not render reminders whose fire_at is in the past" do
        past = create(:reminder, user: user, fire_at: 1.minute.ago)

        get "/voice_commands"

        expect(response.body).not_to include("reminder_#{past.id}")
      end

      it "renders looping reminders ordered by number" do
        high = create(:looping_reminder, user: user, number: 5)
        low  = create(:looping_reminder, user: user, number: 2)

        get "/voice_commands"

        expect(response.body.index("looping_reminder_#{low.id}"))
          .to be < response.body.index("looping_reminder_#{high.id}")
      end

      it "renders all looping reminders regardless of active state" do
        active = create(:looping_reminder, user: user, active: true)
        idle   = create(:looping_reminder, user: user, active: false)

        get "/voice_commands"

        expect(response.body).to include("looping_reminder_#{active.id}")
        expect(response.body).to include("looping_reminder_#{idle.id}")
      end
    end
  end

  describe "POST /voice_commands" do
    context "when not authenticated" do
      it "redirects to login" do
        post "/voice_commands", params: { audio: audio_file }

        expect(response).to redirect_to(login_path)
      end
    end

    context "when authenticated" do
      let(:deepgram) { instance_double(DeepgramClient, transcribe: "what time is it") }
      let(:responder) { instance_double(CommandResponder, respond: audio_bytes) }

      before do
        log_in
        allow(DeepgramClient).to receive(:new).and_return(deepgram)
        allow(CommandResponder).to receive(:new).and_return(responder)
      end

      it "returns audio/mpeg with the synthesized bytes and inline disposition" do
        post "/voice_commands", params: { audio: audio_file }

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to eq("audio/mpeg")
        expect(response.body).to eq(audio_bytes)
        expect(response.headers["Content-Disposition"]).to eq("inline")
      end

      it "transcribes the uploaded audio bytes" do
        post "/voice_commands", params: { audio: audio_file }

        expect(deepgram).to have_received(:transcribe).with(audio: audio_data)
      end

      it "calls respond with the parsed command and current user" do
        post "/voice_commands", params: { audio: audio_file }

        expect(responder).to have_received(:respond)
          .with(command: { intent: :time_check, params: {} }, user: user)
      end

      it "creates a VoiceCommand with correct attributes" do
        expect {
          post "/voice_commands", params: { audio: audio_file }
        }.to change(VoiceCommand, :count).by(1)

        command = VoiceCommand.last
        expect(command.user).to eq(user)
        expect(command.transcript).to eq("what time is it")
        expect(command.intent).to eq("time_check")
        expect(command.params).to eq({})
        expect(command.status).to eq("processed")
      end

      context "when the transcript is a timer command" do
        let(:deepgram) { instance_double(DeepgramClient, transcribe: "set a timer for 5 minutes") }

        it "stores the parsed params on the VoiceCommand" do
          post "/voice_commands", params: { audio: audio_file }

          command = VoiceCommand.last
          expect(command.intent).to eq("timer")
          expect(command.params).to eq({ "minutes" => 5 })
        end
      end

      it "returns 400 when audio param is missing" do
        post "/voice_commands"

        expect(response).to have_http_status(:bad_request)
      end

      it "returns 422 when audio is smaller than 1 KB" do
        tiny = Rack::Test::UploadedFile.new(
          StringIO.new("x" * (1.kilobyte - 1)), "audio/webm", original_filename: "tiny.webm"
        )

        post "/voice_commands", params: { audio: tiny }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "accepts audio that is exactly 1 KB" do
        exactly_1kb = Rack::Test::UploadedFile.new(
          StringIO.new("x" * 1.kilobyte), "audio/webm", original_filename: "min.webm"
        )

        post "/voice_commands", params: { audio: exactly_1kb }

        expect(response).not_to have_http_status(:unprocessable_content)
      end

      it "returns 422 when audio exceeds 1 MB" do
        oversized = Rack::Test::UploadedFile.new(
          StringIO.new("x" * (1.megabyte + 1)), "audio/webm", original_filename: "big.webm"
        )

        post "/voice_commands", params: { audio: oversized }

        expect(response).to have_http_status(:unprocessable_content)
      end

      it "returns 422 when audio has a non-audio MIME type" do
        bad_type = Rack::Test::UploadedFile.new(
          StringIO.new("x" * 1.kilobyte), "text/plain", original_filename: "file.txt"
        )

        post "/voice_commands", params: { audio: bad_type }

        expect(response).to have_http_status(:unprocessable_content)
      end

      context "when the command is not recognised" do
        let(:deepgram) { instance_double(DeepgramClient, transcribe: "blah blah blah") }

        it "sets the X-Status-Text header to the unknown intent message" do
          post "/voice_commands", params: { audio: audio_file }

          expect(response.headers["X-Status-Text"]).to eq(CommandResponder::UNKNOWN_INTENT_MESSAGE)
        end
      end

      context "when Deepgram returns a blank transcript" do
        let(:deepgram)     { instance_double(DeepgramClient, transcribe: "") }
        let(:eleven_labs)  { instance_double(ElevenLabsClient, synthesize: "blank audio") }

        before { allow(ElevenLabsClient).to receive(:new).and_return(eleven_labs) }

        it "returns audio with the status-text header without creating a VoiceCommand" do
          expect {
            post "/voice_commands", params: { audio: audio_file }
          }.not_to change(VoiceCommand, :count)

          expect(response).to have_http_status(:ok)
          expect(response.content_type).to eq("audio/mpeg")
          expect(response.headers["X-Status-Text"]).to eq("Sorry, I didn't catch that.  Please try again.")
        end
      end

      context "when DeepgramClient raises an error" do
        let(:deepgram) { instance_double(DeepgramClient) }

        before { allow(deepgram).to receive(:transcribe).and_raise(DeepgramClient::Error) }

        it "returns 422 without creating a VoiceCommand" do
          expect {
            post "/voice_commands", params: { audio: audio_file }
          }.not_to change(VoiceCommand, :count)

          expect(response).to have_http_status(:unprocessable_content)
        end
      end
    end
  end
end
