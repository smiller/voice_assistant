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

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "accepts audio that is exactly 1 KB" do
        exactly_1kb = Rack::Test::UploadedFile.new(
          StringIO.new("x" * 1.kilobyte), "audio/webm", original_filename: "min.webm"
        )

        post "/voice_commands", params: { audio: exactly_1kb }

        expect(response).not_to have_http_status(:unprocessable_entity)
      end

      it "returns 422 when audio exceeds 1 MB" do
        oversized = Rack::Test::UploadedFile.new(
          StringIO.new("x" * (1.megabyte + 1)), "audio/webm", original_filename: "big.webm"
        )

        post "/voice_commands", params: { audio: oversized }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "returns 422 when audio has a non-audio MIME type" do
        bad_type = Rack::Test::UploadedFile.new(
          StringIO.new("x" * 1.kilobyte), "text/plain", original_filename: "file.txt"
        )

        post "/voice_commands", params: { audio: bad_type }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      context "when Deepgram returns a blank transcript" do
        let(:deepgram) { instance_double(DeepgramClient, transcribe: "") }

        it "returns 400 without creating a VoiceCommand" do
          expect {
            post "/voice_commands", params: { audio: audio_file }
          }.not_to change(VoiceCommand, :count)

          expect(response).to have_http_status(:bad_request)
        end
      end

      context "when DeepgramClient raises an error" do
        let(:deepgram) { instance_double(DeepgramClient) }

        before { allow(deepgram).to receive(:transcribe).and_raise(DeepgramClient::Error) }

        it "returns 422 without creating a VoiceCommand" do
          expect {
            post "/voice_commands", params: { audio: audio_file }
          }.not_to change(VoiceCommand, :count)

          expect(response).to have_http_status(:unprocessable_entity)
        end
      end
    end
  end
end
