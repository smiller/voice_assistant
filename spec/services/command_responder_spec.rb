require "rails_helper"

RSpec.describe CommandResponder do
  let(:tts_client) { instance_double(ElevenLabsClient) }
  let(:geo_client) { instance_double(SunriseSunsetClient) }
  subject(:responder) { described_class.new(tts_client: tts_client, geo_client: geo_client) }

  let(:user) { build(:user, lat: 40.7128, lng: -74.0060, timezone: "America/New_York", elevenlabs_voice_id: "voice123") }
  let(:audio_bytes) { "\xFF\xFB\x90\x00" }

  before do
    allow(tts_client).to receive(:synthesize).and_return(audio_bytes)
  end

  describe "#initialize" do
    it "defaults tts_client to a new ElevenLabsClient instance" do
      client = instance_double(ElevenLabsClient)
      allow(ElevenLabsClient).to receive(:new).and_return(client)
      allow(client).to receive(:synthesize).and_return(audio_bytes)
      allow(SunriseSunsetClient).to receive(:new).and_return(geo_client)

      CommandResponder.new.respond(command: { intent: :time_check, params: {} }, user: user)

      expect(ElevenLabsClient).to have_received(:new)
    end

    it "defaults geo_client to a new SunriseSunsetClient instance" do
      client = instance_double(SunriseSunsetClient)
      allow(SunriseSunsetClient).to receive(:new).and_return(client)
      allow(client).to receive(:sunset_time).and_return(Time.parse("2026-02-23T22:35:00+00:00"))

      CommandResponder.new(tts_client: tts_client).respond(
        command: { intent: :sunset, params: {} }, user: user
      )

      expect(client).to have_received(:sunset_time)
    end
  end

  describe "#respond" do
    context "with a time check command" do
      it "returns synthesized audio of the current time" do
        travel_to Time.new(2026, 2, 23, 14, 11, 0, "-05:00") do
          result = responder.respond(command: { intent: :time_check, params: {} }, user: user)

          expect(result).to eq(audio_bytes)
          expect(tts_client).to have_received(:synthesize)
            .with(text: "The time is 2:11 PM", voice_id: "voice123")
        end
      end
    end

    context "with a sunset command" do
      before do
        allow(geo_client).to receive(:sunset_time).and_return(Time.parse("2026-02-23T22:35:00+00:00"))
      end

      it "returns synthesized audio of the sunset time in the user's timezone" do
        result = responder.respond(command: { intent: :sunset, params: {} }, user: user)

        expect(result).to eq(audio_bytes)
        expect(geo_client).to have_received(:sunset_time).with(lat: user.lat, lng: user.lng)
        expect(tts_client).to have_received(:synthesize)
          .with(text: "Sunset today is at 5:35 PM", voice_id: "voice123")
      end
    end

    context "with an unknown command" do
      it "returns synthesized audio of the fallback message" do
        result = responder.respond(command: { intent: :unknown, params: {} }, user: user)

        expect(result).to eq(audio_bytes)
        expect(tts_client).to have_received(:synthesize)
          .with(text: "Sorry, I didn't understand that", voice_id: "voice123")
      end
    end

    context "with a timer command" do
      let(:user) { create(:user, lat: 40.7128, lng: -74.0060, timezone: "America/New_York", elevenlabs_voice_id: "voice123") }

      it "returns synthesized confirmation audio" do
        result = responder.respond(command: { intent: :timer, params: { minutes: 5 } }, user: user)

        expect(result).to eq(audio_bytes)
        expect(tts_client).to have_received(:synthesize)
          .with(text: "Timer set for 5 minutes", voice_id: "voice123")
      end

      it "uses singular minute when the duration is 1" do
        result = responder.respond(command: { intent: :timer, params: { minutes: 1 } }, user: user)

        expect(result).to eq(audio_bytes)
        expect(tts_client).to have_received(:synthesize)
          .with(text: "Timer set for 1 minute", voice_id: "voice123")
      end

      it "creates a pending Reminder 5 minutes from now" do
        travel_to Time.new(2026, 2, 23, 14, 0, 0, "UTC") do
          expect {
            responder.respond(command: { intent: :timer, params: { minutes: 5 } }, user: user)
          }.to change(Reminder, :count).by(1)

          reminder = Reminder.last
          expect(reminder.user).to eq(user)
          expect(reminder.kind).to eq("timer")
          expect(reminder.message).to eq("Timer finished after 5 minutes")
          expect(reminder.fire_at).to eq(5.minutes.from_now)
          expect(reminder.recurs_daily).to be(false)
          expect(reminder.status).to eq("pending")
        end
      end

      it "creates a Reminder with singular 'minute' in the message for a 1-minute timer" do
        travel_to Time.new(2026, 2, 23, 14, 0, 0, "UTC") do
          responder.respond(command: { intent: :timer, params: { minutes: 1 } }, user: user)

          expect(Reminder.last.message).to eq("Timer finished after 1 minute")
        end
      end

      it "enqueues a ReminderJob scheduled 5 minutes from now with the reminder id" do
        travel_to Time.new(2026, 2, 23, 14, 0, 0, "UTC") do
          expect {
            responder.respond(command: { intent: :timer, params: { minutes: 5 } }, user: user)
          }.to have_enqueued_job(ReminderJob).at(5.minutes.from_now).with(be_a(Integer))
        end
      end
    end

    context "with a reminder command" do
      let(:user) { create(:user, lat: 40.7128, lng: -74.0060, timezone: "America/New_York", elevenlabs_voice_id: "voice123") }

      it "returns synthesized confirmation audio" do
        travel_to Time.new(2026, 2, 23, 0, 0, 0, "UTC") do
          result = responder.respond(command: { intent: :reminder, params: { hour: 21, minute: 0, message: "take medication" } }, user: user)

          expect(result).to eq(audio_bytes)
          expect(tts_client).to have_received(:synthesize)
            .with(text: "Reminder set for 9 PM to take medication", voice_id: "voice123")
        end
      end

      it "creates a pending Reminder at the specified time in user timezone" do
        travel_to Time.new(2026, 2, 23, 12, 0, 0, "UTC") do
          responder.respond(command: { intent: :reminder, params: { hour: 21, minute: 0, message: "take medication" } }, user: user)

          reminder = Reminder.last
          expect(reminder.kind).to eq("reminder")
          expect(reminder.message).to eq("take medication")
          expected_fire_at = Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 21, 0, 0) }
          expect(reminder.fire_at).to be_within(1.second).of(expected_fire_at)
          expect(reminder.recurs_daily).to be(false)
        end
      end

      it "schedules for today when the reminder time is a few minutes away" do
        travel_to Time.new(2026, 2, 23, 23, 0, 0, "UTC") do
          responder.respond(command: { intent: :reminder, params: { hour: 18, minute: 5, message: "check messages" } }, user: user)

          expected_fire_at = Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 18, 5, 0) }
          expect(Reminder.last.fire_at).to be_within(1.second).of(expected_fire_at)
        end
      end

      it "preserves non-zero minutes in the fire_at time" do
        travel_to Time.new(2026, 2, 23, 12, 0, 0, "UTC") do
          responder.respond(command: { intent: :reminder, params: { hour: 21, minute: 30, message: "take medication" } }, user: user)

          reminder = Reminder.last
          expected_fire_at = Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 21, 30, 0) }
          expect(reminder.fire_at).to be_within(1.second).of(expected_fire_at)
        end
      end
    end

    context "when user timezone differs from the server timezone" do
      let(:user) { create(:user, timezone: "Pacific Time (US & Canada)", elevenlabs_voice_id: "voice123") }

      it "uses the user's timezone (not the server timezone) to compute fire_at" do
        travel_to Time.new(2026, 2, 23, 12, 0, 0, "UTC") do
          responder.respond(command: { intent: :reminder, params: { hour: 21, minute: 0, message: "meditate" } }, user: user)

          expected_fire_at = Time.use_zone("Pacific Time (US & Canada)") { Time.zone.local(2026, 2, 23, 21, 0, 0) }
          expect(Reminder.last.fire_at).to be_within(1.second).of(expected_fire_at)
        end
      end
    end

    context "when user timezone is stored as Rails name (Eastern Time (US & Canada))" do
      let(:user) { create(:user, timezone: "Eastern Time (US & Canada)", elevenlabs_voice_id: "voice123") }

      it "schedules for today, not tomorrow" do
        travel_to Time.new(2026, 2, 23, 23, 0, 0, "UTC") do
          responder.respond(command: { intent: :reminder, params: { hour: 18, minute: 5, message: "check messages" } }, user: user)

          expected_fire_at = Time.use_zone("Eastern Time (US & Canada)") { Time.zone.local(2026, 2, 23, 18, 5, 0) }
          expect(Reminder.last.fire_at).to be_within(1.second).of(expected_fire_at)
        end
      end
    end

    context "when UTC date is ahead of the user's local date" do
      let(:user) { create(:user, timezone: "America/New_York", elevenlabs_voice_id: "voice123") }

      it "schedules using the user's local date, not the UTC date" do
        travel_to Time.new(2026, 2, 24, 1, 0, 0, "UTC") do
          responder.respond(command: { intent: :reminder, params: { hour: 21, minute: 0, message: "take medication" } }, user: user)

          expected_fire_at = Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 21, 0, 0) }
          expect(Reminder.last.fire_at).to be_within(1.second).of(expected_fire_at)
        end
      end
    end

    context "when UTC date is ahead of user's local date and reminder time has already passed locally" do
      let(:user) { create(:user, timezone: "America/New_York", elevenlabs_voice_id: "voice123") }

      it "says tomorrow in the reminder confirmation using the user's local date" do
        travel_to Time.new(2026, 2, 24, 1, 0, 0, "UTC") do
          responder.respond(command: { intent: :reminder, params: { hour: 8, minute: 0, message: "exercise" } }, user: user)

          expect(tts_client).to have_received(:synthesize)
            .with(text: "Reminder set for 8 AM tomorrow to exercise", voice_id: "voice123")
        end
      end

      it "says tomorrow in the daily reminder confirmation using the user's local date" do
        travel_to Time.new(2026, 2, 24, 1, 0, 0, "UTC") do
          responder.respond(command: { intent: :daily_reminder, params: { hour: 8, minute: 0, message: "exercise" } }, user: user)

          expect(tts_client).to have_received(:synthesize)
            .with(text: "Daily reminder: 8 AM - exercise", voice_id: "voice123")
        end
      end
    end

    context "when the reminder time has already passed today" do
      let(:user) { create(:user, timezone: "America/New_York", elevenlabs_voice_id: "voice123") }

      it "says tomorrow in the confirmation" do
        travel_to Time.new(2026, 2, 23, 13, 0, 0, "UTC") do
          responder.respond(command: { intent: :reminder, params: { hour: 7, minute: 0, message: "take medication" } }, user: user)

          expect(tts_client).to have_received(:synthesize)
            .with(text: "Reminder set for 7 AM tomorrow to take medication", voice_id: "voice123")
        end
      end

      it "creates the Reminder with fire_at tomorrow" do
        travel_to Time.new(2026, 2, 23, 13, 0, 0, "UTC") do
          responder.respond(command: { intent: :reminder, params: { hour: 7, minute: 0, message: "take medication" } }, user: user)

          expected_fire_at = Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 24, 7, 0, 0) }
          expect(Reminder.last.fire_at).to be_within(1.second).of(expected_fire_at)
        end
      end

      it "says tomorrow in a daily reminder confirmation" do
        travel_to Time.new(2026, 2, 23, 13, 0, 0, "UTC") do
          responder.respond(command: { intent: :daily_reminder, params: { hour: 7, minute: 0, message: "write morning pages" } }, user: user)

          expect(tts_client).to have_received(:synthesize)
            .with(text: "Daily reminder: 7 AM - write morning pages", voice_id: "voice123")
        end
      end
    end

    context "with a daily reminder command" do
      let(:user) { create(:user, lat: 40.7128, lng: -74.0060, timezone: "America/New_York", elevenlabs_voice_id: "voice123") }

      it "returns synthesized confirmation audio" do
        travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do
          result = responder.respond(command: { intent: :daily_reminder, params: { hour: 7, minute: 0, message: "write morning pages" } }, user: user)

          expect(result).to eq(audio_bytes)
          expect(tts_client).to have_received(:synthesize)
            .with(text: "Daily reminder: 7 AM - write morning pages", voice_id: "voice123")
        end
      end

      it "formats with minutes when non-zero" do
        travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do
          responder.respond(command: { intent: :daily_reminder, params: { hour: 23, minute: 0, message: "do lights out" } }, user: user)

          expect(tts_client).to have_received(:synthesize)
            .with(text: "Daily reminder: 11 PM - do lights out", voice_id: "voice123")
        end
      end

      it "creates a Reminder with recurs_daily: true and kind: daily_reminder" do
        travel_to Time.new(2026, 2, 23, 12, 0, 0, "UTC") do
          responder.respond(command: { intent: :daily_reminder, params: { hour: 7, minute: 0, message: "write morning pages" } }, user: user)

          reminder = Reminder.last
          expect(reminder.kind).to eq("daily_reminder")
          expect(reminder.message).to eq("write morning pages")
          expect(reminder.recurs_daily).to be(true)
        end
      end
    end

    context "with a reminder at a non-zero minute" do
      it "includes the minutes in the confirmation text" do
        travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do
          responder.respond(command: { intent: :reminder, params: { hour: 21, minute: 30, message: "check in" } }, user: user)

          expect(tts_client).to have_received(:synthesize)
            .with(text: "Reminder set for 9:30 PM to check in", voice_id: "voice123")
        end
      end
    end

    context "with an 11am reminder command" do
      it "formats the time as AM" do
        travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do
          result = responder.respond(command: { intent: :reminder, params: { hour: 11, minute: 0, message: "stretch" } }, user: user)

          expect(result).to eq(audio_bytes)
          expect(tts_client).to have_received(:synthesize)
            .with(text: "Reminder set for 11 AM to stretch", voice_id: "voice123")
        end
      end
    end

    context "with a noon reminder command" do
      it "formats noon as 12:00 PM" do
        travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do
          result = responder.respond(command: { intent: :reminder, params: { hour: 12, minute: 0, message: "eat lunch" } }, user: user)

          expect(result).to eq(audio_bytes)
          expect(tts_client).to have_received(:synthesize)
            .with(text: "Reminder set for 12 PM to eat lunch", voice_id: "voice123")
        end
      end
    end

    context "with a midnight reminder command" do
      it "formats midnight as 12:00 AM" do
        travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do
          result = responder.respond(command: { intent: :reminder, params: { hour: 0, minute: 0, message: "sleep" } }, user: user)

          expect(result).to eq(audio_bytes)
          expect(tts_client).to have_received(:synthesize)
            .with(text: "Reminder set for 12 AM to sleep", voice_id: "voice123")
        end
      end
    end

    context "broadcast on schedule" do
      let(:user) { create(:user, timezone: "America/New_York", elevenlabs_voice_id: "voice123") }

      before { allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) }

      it "broadcasts a timer append to the timers target" do
        travel_to Time.new(2026, 2, 23, 14, 0, 0, "UTC") do
          responder.respond(command: { intent: :timer, params: { minutes: 5 } }, user: user)

          expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
            .with(user, target: "timers", partial: "reminders/reminder",
                  locals: { reminder: instance_of(Reminder) })
        end
      end

      it "broadcasts a reminder append to the reminders target" do
        travel_to Time.new(2026, 2, 23, 12, 0, 0, "UTC") do
          responder.respond(
            command: { intent: :reminder, params: { hour: 21, minute: 0, message: "take medication" } },
            user: user
          )

          expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
            .with(user, target: "reminders", partial: "reminders/reminder",
                  locals: { reminder: instance_of(Reminder) })
        end
      end

      it "broadcasts a daily reminder append to the daily_reminders target" do
        travel_to Time.new(2026, 2, 23, 12, 0, 0, "UTC") do
          responder.respond(
            command: { intent: :daily_reminder, params: { hour: 7, minute: 0, message: "exercise" } },
            user: user
          )

          expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
            .with(user, target: "daily_reminders", partial: "reminders/reminder",
                  locals: { reminder: instance_of(Reminder) })
        end
      end

      it "does not broadcast for non-scheduling commands" do
        responder.respond(command: { intent: :time_check, params: {} }, user: user)

        expect(Turbo::StreamsChannel).not_to have_received(:broadcast_append_to)
      end

      context "when a later-firing reminder already exists" do
        let(:later) do
          create(:reminder, user: user, message: "later event",
                 fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 22, 0, 0) })
        end

        before do
          allow(Turbo::StreamsChannel).to receive(:broadcast_before_to)
          later  # ensure created before respond is called
        end

        it "broadcasts before the existing later reminder instead of appending" do
          travel_to Time.new(2026, 2, 23, 12, 0, 0, "UTC") do
            responder.respond(
              command: { intent: :reminder, params: { hour: 21, minute: 0, message: "take medication" } },
              user: user
            )

            new_reminder = Reminder.find_by(message: "take medication")
            expect(Turbo::StreamsChannel).to have_received(:broadcast_before_to)
              .with(user, target: ActionView::RecordIdentifier.dom_id(later),
                    partial: "reminders/reminder", locals: { reminder: new_reminder })
          end
        end

        it "does not broadcast_append_to the reminders list when inserting before a sibling" do
          travel_to Time.new(2026, 2, 23, 12, 0, 0, "UTC") do
            responder.respond(
              command: { intent: :reminder, params: { hour: 21, minute: 0, message: "take medication" } },
              user: user
            )

            expect(Turbo::StreamsChannel).not_to have_received(:broadcast_append_to)
              .with(user, hash_including(target: "reminders"))
          end
        end
      end

      context "when a later-time-of-day daily reminder already exists" do
        let(:later_daily) do
          create(:reminder, :daily, user: user, message: "later daily event",
                 fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 23, 0, 0) })
        end

        before do
          allow(Turbo::StreamsChannel).to receive(:broadcast_before_to)
          later_daily
        end

        it "broadcasts daily reminder before the existing later sibling" do
          travel_to Time.new(2026, 2, 23, 5, 0, 0, "UTC") do
            responder.respond(
              command: { intent: :daily_reminder, params: { hour: 7, minute: 0, message: "write morning pages" } },
              user: user
            )

            new_reminder = Reminder.find_by(message: "write morning pages")
            expect(Turbo::StreamsChannel).to have_received(:broadcast_before_to)
              .with(user, target: ActionView::RecordIdentifier.dom_id(later_daily),
                    partial: "reminders/reminder", locals: { reminder: new_reminder })
          end
        end
      end
    end
  end
end
