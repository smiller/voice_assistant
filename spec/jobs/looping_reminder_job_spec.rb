require "rails_helper"

RSpec.describe LoopingReminderJob do
  let(:tts_client) { instance_double(ElevenLabsClient) }
  let(:user) { create(:user, elevenlabs_voice_id: "voice123") }
  let(:loop) { create(:looping_reminder, user: user, interval_minutes: 5, message: "have you done the dishes?", active: true) }
  let(:audio_bytes) { "\xFF\xFB\x90\x00".b }
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }
  let(:scheduled_fire_at) { Time.current }

  before do
    allow(ElevenLabsClient).to receive(:new).and_return(tts_client)
    allow(tts_client).to receive(:synthesize).and_return(audio_bytes)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Rails).to receive(:cache).and_return(cache_store)
    allow(described_class).to receive(:set).and_return(double(perform_later: nil))
  end

  describe "#perform" do
    context "when the looping reminder does not exist" do
      it "does nothing" do
        expect { described_class.perform_now(0, scheduled_fire_at) }.not_to raise_error
        expect(tts_client).not_to have_received(:synthesize)
      end
    end

    context "when the looping reminder is inactive" do
      before { loop.stop! }

      it "does not synthesize audio" do
        described_class.perform_now(loop.id, scheduled_fire_at)

        expect(tts_client).not_to have_received(:synthesize)
      end

      it "does not re-enqueue itself" do
        described_class.perform_now(loop.id, scheduled_fire_at)

        expect(described_class).not_to have_received(:set)
      end
    end

    context "when the looping reminder is active" do
      it "synthesizes the loop message" do
        described_class.perform_now(loop.id, scheduled_fire_at)

        expect(tts_client).to have_received(:synthesize).with(
          text: loop.message,
          voice_id: user.elevenlabs_voice_id
        )
      end

      it "writes audio to cache under a hex token key expiring in 5 minutes" do
        allow(SecureRandom).to receive(:hex).and_return("abc123")

        described_class.perform_now(loop.id, scheduled_fire_at)

        expect(cache_store.read("looping_reminder_audio_abc123")).to eq(audio_bytes)
      end

      it "caches audio expiring exactly at 5 minutes" do
        allow(SecureRandom).to receive(:hex).and_return("tok1")
        base_time = Time.current

        travel_to(base_time) do
          described_class.perform_now(loop.id, scheduled_fire_at)
        end

        # Still present just before 5 minutes
        travel_to(base_time + 4.minutes + 59.seconds) do
          expect(cache_store.read("looping_reminder_audio_tok1")).not_to be_nil
        end

        # Gone after 5 minutes
        travel_to(base_time + 5.minutes + 1.second) do
          expect(cache_store.read("looping_reminder_audio_tok1")).to be_nil
        end
      end

      it "broadcasts to voice_alerts with the token in locals" do
        allow(SecureRandom).to receive(:hex).and_return("mytoken")

        described_class.perform_now(loop.id, scheduled_fire_at)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to).with(
          user,
          target: "voice_alerts",
          partial: "voice_alerts/alert",
          locals: { token: "mytoken" }
        )
      end

      it "re-enqueues itself at scheduled_fire_at + interval" do
        next_fire_at = scheduled_fire_at + 5.minutes

        described_class.perform_now(loop.id, scheduled_fire_at)

        expect(described_class).to have_received(:set).with(wait_until: next_fire_at)
      end

      it "uses scheduled_fire_at for drift-free interval calculation" do
        old_fire = 1.hour.ago
        next_expected = old_fire + 5.minutes

        described_class.perform_now(loop.id, old_fire)

        expect(described_class).to have_received(:set).with(wait_until: next_expected)
      end
    end

    context "when ElevenLabsClient raises an error" do
      before { allow(tts_client).to receive(:synthesize).and_raise(ElevenLabsClient::Error) }

      it "discards the job without raising" do
        expect { described_class.perform_now(loop.id, scheduled_fire_at) }.not_to raise_error
      end

      it "does not re-enqueue" do
        described_class.perform_now(loop.id, scheduled_fire_at)

        expect(described_class).not_to have_received(:set)
      end
    end
  end
end
