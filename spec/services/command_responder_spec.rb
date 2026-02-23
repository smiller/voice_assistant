require "rails_helper"

RSpec.describe CommandResponder do
  let(:tts_client) { instance_double(ElevenLabsClient) }
  subject(:responder) { described_class.new(tts_client: tts_client) }

  let(:user) { build(:user, lat: 40.7128, lng: -74.0060, timezone: "America/New_York", elevenlabs_voice_id: "voice123") }
  let(:audio_bytes) { "\xFF\xFB\x90\x00" }

  before do
    allow(tts_client).to receive(:synthesize).and_return(audio_bytes)
  end

  describe "#respond" do
    context "with a time check transcript" do
      it "returns synthesized audio of the current time" do
        travel_to Time.new(2026, 2, 23, 14, 11, 0, "-05:00") do
          result = responder.respond(transcript: "what time is it", user: user)

          expect(result).to eq(audio_bytes)
          expect(tts_client).to have_received(:synthesize)
            .with(text: "The time is 2:11 PM", voice_id: "voice123")
        end
      end
    end

    context "with a sunset transcript" do
      let(:sunset_client) { instance_double(SunriseSunsetClient) }

      before do
        allow(SunriseSunsetClient).to receive(:new).and_return(sunset_client)
        allow(sunset_client).to receive(:sunset_time).and_return(Time.parse("2026-02-23T22:35:00+00:00"))
      end

      it "returns synthesized audio of the sunset time in the user's timezone" do
        result = responder.respond(transcript: "when is sunset", user: user)

        expect(result).to eq(audio_bytes)
        expect(sunset_client).to have_received(:sunset_time).with(lat: user.lat, lng: user.lng)
        expect(tts_client).to have_received(:synthesize)
          .with(text: "Sunset today is at 5:35 PM", voice_id: "voice123")
      end
    end

    context "with an unknown transcript" do
      it "returns synthesized audio of the fallback message" do
        result = responder.respond(transcript: "xyzzy", user: user)

        expect(result).to eq(audio_bytes)
        expect(tts_client).to have_received(:synthesize)
          .with(text: "I didn't understand that", voice_id: "voice123")
      end
    end

    context "with a timer transcript" do
      it "returns synthesized confirmation audio" do
        result = responder.respond(transcript: "set a timer for 5 minutes", user: user)

        expect(result).to eq(audio_bytes)
        expect(tts_client).to have_received(:synthesize)
          .with(text: "Timer set for 5 minutes", voice_id: "voice123")
      end
    end

    context "with a reminder transcript" do
      it "returns synthesized confirmation audio" do
        result = responder.respond(transcript: "set a 9pm reminder to take medication", user: user)

        expect(result).to eq(audio_bytes)
        expect(tts_client).to have_received(:synthesize)
          .with(text: "Reminder set for 9:00 PM to take medication", voice_id: "voice123")
      end
    end

    context "with a daily reminder transcript" do
      it "returns synthesized confirmation audio" do
        result = responder.respond(transcript: "set a daily 7am reminder to write morning pages", user: user)

        expect(result).to eq(audio_bytes)
        expect(tts_client).to have_received(:synthesize)
          .with(text: "Daily reminder set for 7:00 AM to write morning pages", voice_id: "voice123")
      end
    end

    context "with an 11am reminder transcript" do
      it "formats the time as AM" do
        result = responder.respond(transcript: "set a 11am reminder to stretch", user: user)

        expect(result).to eq(audio_bytes)
        expect(tts_client).to have_received(:synthesize)
          .with(text: "Reminder set for 11:00 AM to stretch", voice_id: "voice123")
      end
    end

    context "with a noon reminder transcript" do
      it "formats noon as 12:00 PM" do
        result = responder.respond(transcript: "set a 12pm reminder to eat lunch", user: user)

        expect(result).to eq(audio_bytes)
        expect(tts_client).to have_received(:synthesize)
          .with(text: "Reminder set for 12:00 PM to eat lunch", voice_id: "voice123")
      end
    end

    context "with a midnight reminder transcript" do
      it "formats midnight as 12:00 AM" do
        result = responder.respond(transcript: "set a 12am reminder to sleep", user: user)

        expect(result).to eq(audio_bytes)
        expect(tts_client).to have_received(:synthesize)
          .with(text: "Reminder set for 12:00 AM to sleep", voice_id: "voice123")
      end
    end
  end
end
