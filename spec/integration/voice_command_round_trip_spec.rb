require "rails_helper"

RSpec.describe "Voice command round trip", type: :request do
  let(:user) { create(:user, elevenlabs_voice_id: "voice123", timezone: "America/New_York") }
  let(:audio_bytes) { "\xFF\xFB\x90\x00response".b }
  let(:tts) { instance_double(ElevenLabsClient, synthesize: audio_bytes) }
  let(:audio_file) do
    Rack::Test::UploadedFile.new(StringIO.new(("fake audio" + "x" * 1.kilobyte).b), "audio/webm", original_filename: "rec.webm")
  end

  before do
    post "/session", params: { email: user.email, password: "s3cr3tpassword" }
    allow(ElevenLabsClient).to receive(:new).and_return(tts)
  end

  context "with a time check transcript" do
    before do
      allow(DeepgramClient).to receive(:new).and_return(
        instance_double(DeepgramClient, transcribe: "what time is it")
      )
    end

    it "synthesizes and returns the current time as audio" do
      travel_to Time.new(2026, 2, 23, 14, 11, 0, "-05:00") do
        post "/voice_commands", params: { audio: audio_file }

        expect(response.content_type).to eq("audio/mpeg")
        expect(response.body.b).to eq(audio_bytes)
        expect(tts).to have_received(:synthesize)
          .with(text: "The time is 2:11 PM", voice_id: "voice123")
      end
    end
  end

  context "with a timer transcript" do
    before do
      allow(DeepgramClient).to receive(:new).and_return(
        instance_double(DeepgramClient, transcribe: "set a timer for 5 minutes")
      )
    end

    it "returns confirmation audio, creates a Reminder, and enqueues ReminderJob" do
      travel_to Time.new(2026, 2, 23, 14, 0, 0, "UTC") do
        expect {
          post "/voice_commands", params: { audio: audio_file }
        }.to change(Reminder, :count).by(1)

        expect(response.content_type).to eq("audio/mpeg")
        expect(tts).to have_received(:synthesize)
          .with(text: "Timer set for 5 minutes", voice_id: "voice123")
        expect(ReminderJob).to have_been_enqueued.at(5.minutes.from_now)
      end
    end
  end

  context "with a reminder transcript" do
    before do
      allow(DeepgramClient).to receive(:new).and_return(
        instance_double(DeepgramClient, transcribe: "set a 9pm reminder to take medication")
      )
    end

    it "returns confirmation audio and creates a Reminder at the specified time in user timezone" do
      travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do
        post "/voice_commands", params: { audio: audio_file }

        expect(response.content_type).to eq("audio/mpeg")
        expect(tts).to have_received(:synthesize)
          .with(text: "Reminder set for 9 PM to take medication", voice_id: "voice123")

        expected_fire_at = Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 21, 0, 0) }
        expect(Reminder.last.fire_at).to be_within(1.second).of(expected_fire_at)
      end
    end
  end
end
