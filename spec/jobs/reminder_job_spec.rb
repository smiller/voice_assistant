require "rails_helper"

RSpec.describe ReminderJob do
  let(:tts_client) { instance_double(ElevenLabsClient) }
  let(:user) { create(:user, elevenlabs_voice_id: "voice123") }
  let(:reminder) { create(:reminder, user: user, kind: :reminder, message: "take medication", fire_at: 1.hour.from_now) }
  let(:audio_bytes) { "\xFF\xFB\x90\x00".b }

  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(ElevenLabsClient).to receive(:new).and_return(tts_client)
    allow(tts_client).to receive(:synthesize).and_return(audio_bytes)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Rails).to receive(:cache).and_return(cache_store)
  end

  describe "#perform" do
    context "when reminder does not exist" do
      it "does nothing" do
        expect { described_class.perform_now(0) }.not_to raise_error
        expect(tts_client).not_to have_received(:synthesize)
      end
    end

    context "when reminder is already delivered" do
      before { reminder.delivered! }

      it "does nothing" do
        described_class.perform_now(reminder.id)

        expect(tts_client).not_to have_received(:synthesize)
      end
    end

    context "when reminder is cancelled" do
      before { reminder.cancelled! }

      it "does nothing" do
        described_class.perform_now(reminder.id)

        expect(tts_client).not_to have_received(:synthesize)
      end
    end

    context "when reminder is pending" do
      it "synthesizes audio prefixed with the current time in the user's timezone" do
        travel_to Time.new(2026, 2, 23, 21, 0, 0, "UTC") do  # 4:00 PM ET
          described_class.perform_now(reminder.id)

          expect(tts_client).to have_received(:synthesize)
            .with(text: "It's 4:00 PM. Reminder: take medication", voice_id: "voice123")
        end
      end

      it "stores audio in Rails cache under a token key" do
        allow(SecureRandom).to receive(:hex).and_return("abc123")

        described_class.perform_now(reminder.id)

        expect(Rails.cache.read("reminder_audio_abc123")).to eq(audio_bytes)
      end

      it "stores audio with a 5-minute expiry" do
        allow(SecureRandom).to receive(:hex).and_return("abc123")
        allow(cache_store).to receive(:write).and_call_original

        described_class.perform_now(reminder.id)

        expect(cache_store).to have_received(:write)
          .with("reminder_audio_abc123", audio_bytes, expires_in: 5.minutes)
      end

      it "broadcasts a Turbo Stream append to the user with the token" do
        allow(SecureRandom).to receive(:hex).and_return("abc123")

        described_class.perform_now(reminder.id)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
          .with(user, target: "voice_alerts", partial: "voice_alerts/alert", locals: { token: "abc123" })
      end

      it "marks the reminder as delivered" do
        described_class.perform_now(reminder.id)

        expect(reminder.reload.status).to eq("delivered")
      end

      it "does not re-enqueue when recurs_daily is false" do
        expect {
          described_class.perform_now(reminder.id)
        }.not_to have_enqueued_job(described_class)
      end
    end

    context "when reminder is a daily_reminder kind" do
      let(:reminder) do
        create(:reminder, user: user, kind: :daily_reminder,
          message: "write morning pages", fire_at: 1.hour.from_now, recurs_daily: true)
      end

      it "synthesizes audio prefixed with the current time in the user's timezone" do
        travel_to Time.new(2026, 2, 23, 12, 0, 0, "UTC") do  # 7:00 AM ET
          described_class.perform_now(reminder.id)

          expect(tts_client).to have_received(:synthesize)
            .with(text: "It's 7:00 AM. Reminder: write morning pages", voice_id: "voice123")
        end
      end
    end

    context "when reminder is a timer kind" do
      let(:reminder) do
        create(:reminder, user: user, kind: :timer,
          message: "Timer finished after 5 minutes", fire_at: 1.hour.from_now)
      end

      it "synthesizes the message without a time prefix" do
        described_class.perform_now(reminder.id)

        expect(tts_client).to have_received(:synthesize)
          .with(text: "Timer finished after 5 minutes", voice_id: "voice123")
      end
    end

    context "when reminder recurs daily" do
      let(:reminder) do
        create(:reminder, user: user, kind: :daily_reminder, message: "write morning pages",
          fire_at: Time.new(2026, 2, 23, 7, 0, 0, "UTC"), recurs_daily: true)
      end

      it "enqueues a new ReminderJob for tomorrow at the same time with an integer id" do
        travel_to Time.new(2026, 2, 23, 7, 0, 0, "UTC") do
          described_class.perform_now(reminder.id)

          expect(described_class).to have_been_enqueued.at(1.day.from_now).with(be_a(Integer))
        end
      end

      it "creates a new Reminder record for tomorrow with recurs_daily: true" do
        travel_to Time.new(2026, 2, 23, 7, 0, 0, "UTC") do
          original_id = reminder.id
          described_class.perform_now(reminder.id)

          tomorrow = Reminder.where("id > ?", original_id).first
          expect(tomorrow.fire_at).to be_within(1.second).of(reminder.fire_at + 1.day)
          expect(tomorrow.message).to eq(reminder.message)
          expect(tomorrow.kind).to eq(reminder.kind)
          expect(tomorrow.user).to eq(user)
          expect(tomorrow.recurs_daily).to be(true)
        end
      end
    end
  end
end
