require "rails_helper"

RSpec.describe CommandResponder do
  let(:tts_client) { instance_double(ElevenLabsClient) }
  let(:geo_client) { instance_double(SunriseSunsetClient) }
  subject(:responder) { described_class.new(tts_client: tts_client, geo_client: geo_client) }

  let(:user) { create(:user, :voiced, :located) }
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

      it "returns 'Sorry' when error is present but not :replacement_phrase_taken" do
        responder.respond(command: { intent: :unknown, params: { error: :some_other_error } }, user: user)

        expect(tts_client).to have_received(:synthesize)
          .with(text: "Sorry, I didn't understand that", voice_id: user.elevenlabs_voice_id)
      end
    end

    context "with a timer command" do
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
      let(:user) { create(:user, :voiced, timezone: "Pacific Time (US & Canada)") }

      it "uses the user's timezone (not the server timezone) to compute fire_at" do
        travel_to Time.new(2026, 2, 23, 12, 0, 0, "UTC") do
          responder.respond(command: { intent: :reminder, params: { hour: 21, minute: 0, message: "meditate" } }, user: user)

          expected_fire_at = Time.use_zone("Pacific Time (US & Canada)") { Time.zone.local(2026, 2, 23, 21, 0, 0) }
          expect(Reminder.last.fire_at).to be_within(1.second).of(expected_fire_at)
        end
      end
    end

    context "when user timezone is stored as Rails name (Eastern Time (US & Canada))" do
      let(:user) { create(:user, :voiced, timezone: "Eastern Time (US & Canada)") }

      it "schedules for today, not tomorrow" do
        travel_to Time.new(2026, 2, 23, 23, 0, 0, "UTC") do
          responder.respond(command: { intent: :reminder, params: { hour: 18, minute: 5, message: "check messages" } }, user: user)

          expected_fire_at = Time.use_zone("Eastern Time (US & Canada)") { Time.zone.local(2026, 2, 23, 18, 5, 0) }
          expect(Reminder.last.fire_at).to be_within(1.second).of(expected_fire_at)
        end
      end
    end

    context "when UTC date is ahead of the user's local date" do
      it "schedules using the user's local date, not the UTC date" do
        travel_to Time.new(2026, 2, 24, 1, 0, 0, "UTC") do
          responder.respond(command: { intent: :reminder, params: { hour: 21, minute: 0, message: "take medication" } }, user: user)

          expected_fire_at = Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 21, 0, 0) }
          expect(Reminder.last.fire_at).to be_within(1.second).of(expected_fire_at)
        end
      end
    end

    context "when UTC date is ahead of user's local date and reminder time has already passed locally" do
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
      before { allow(Turbo::StreamsChannel).to receive(:broadcast_append_to) }

      {
        timer:          [ { minutes: 5 },                                      "timers",          Time.new(2026, 2, 23, 14, 0, 0, "UTC") ],
        reminder:       [ { hour: 21, minute: 0, message: "take medication" }, "reminders",       Time.new(2026, 2, 23, 12, 0, 0, "UTC") ],
        daily_reminder: [ { hour: 7,  minute: 0, message: "exercise" },        "daily_reminders", Time.new(2026, 2, 23, 12, 0, 0, "UTC") ]
      }.each do |intent, (params, target, time)|
        it "broadcasts #{intent} append to the #{target} target" do
          travel_to time do
            responder.respond(command: { intent: intent, params: params }, user: user)

            expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to)
              .with(user, target: target, partial: "reminders/reminder",
                    locals: { reminder: instance_of(Reminder) })
          end
        end
      end

      it "does not broadcast for non-scheduling commands" do
        responder.respond(command: { intent: :time_check, params: {} }, user: user)

        expect(Turbo::StreamsChannel).not_to have_received(:broadcast_append_to)
      end

      shared_examples "broadcasts before later_sibling" do
        it "broadcasts before the later_sibling instead of appending" do
          travel_to insert_time do
            responder.respond(command: insert_command, user: user)

            inserted = Reminder.find_by(message: inserted_message)
            expect(Turbo::StreamsChannel).to have_received(:broadcast_before_to)
              .with(user, target: ActionView::RecordIdentifier.dom_id(later_sibling),
                    partial: "reminders/reminder", locals: { reminder: inserted })
          end
        end
      end

      context "when a later-firing reminder already exists" do
        let(:later_sibling) do
          create(:reminder, user: user, message: "later event",
                 fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 22, 0, 0) })
        end
        let(:insert_time)      { Time.new(2026, 2, 23, 12, 0, 0, "UTC") }
        let(:insert_command)   { { intent: :reminder, params: { hour: 21, minute: 0, message: "take medication" } } }
        let(:inserted_message) { "take medication" }

        before do
          allow(Turbo::StreamsChannel).to receive(:broadcast_before_to)
          later_sibling
        end

        it_behaves_like "broadcasts before later_sibling"

        it "does not broadcast_append_to the reminders list when inserting before a later_sibling" do
          travel_to insert_time do
            responder.respond(command: insert_command, user: user)

            expect(Turbo::StreamsChannel).not_to have_received(:broadcast_append_to)
              .with(user, hash_including(target: "reminders"))
          end
        end
      end

      context "when a later-time-of-day daily reminder already exists" do
        let(:later_sibling) do
          create(:reminder, :daily, user: user, message: "later daily event",
                 fire_at: Time.use_zone("America/New_York") { Time.zone.local(2026, 2, 23, 23, 0, 0) })
        end
        let(:insert_time)      { Time.new(2026, 2, 23, 5, 0, 0, "UTC") }
        let(:insert_command)   { { intent: :daily_reminder, params: { hour: 7, minute: 0, message: "write morning pages" } } }
        let(:inserted_message) { "write morning pages" }

        before do
          allow(Turbo::StreamsChannel).to receive(:broadcast_before_to)
          later_sibling
        end

        it_behaves_like "broadcasts before later_sibling"
      end
    end
  end

  describe "#respond with loop commands" do
    before do
      allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
      allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
      allow(LoopingReminderJob).to receive(:set).and_return(double(perform_later: nil))
    end

    shared_examples "broadcasts loop replace" do
      it "broadcasts replace to update the loop row with correct partial and locals" do
        responder.respond(command: loop_command, user: user)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
          user,
          target: "looping_reminder_#{reminder.id}",
          partial: "looping_reminders/looping_reminder",
          locals: { looping_reminder: reminder }
        )
      end
    end

    shared_examples "schedules LoopingReminderJob" do
      it "schedules LoopingReminderJob with exact timing, loop id, and epoch" do
        freeze_time do
          job_proxy = double("job_proxy", perform_later: nil)
          allow(LoopingReminderJob).to receive(:set).and_return(job_proxy)

          responder.respond(command: loop_command, user: user)
          created_reminder = LoopingReminder.last

          expect(LoopingReminderJob).to have_received(:set)
            .with(wait_until: created_reminder.interval_minutes.minutes.from_now)
          expect(job_proxy).to have_received(:perform_later)
            .with(created_reminder.id, created_reminder.interval_minutes.minutes.from_now, created_reminder.job_epoch)
        end
      end
    end

    shared_examples "broadcasts loop append" do
      it "broadcasts append to looping_reminders list with correct partial and locals" do
        responder.respond(command: loop_command, user: user)
        created_reminder = LoopingReminder.last

        expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to).with(
          user,
          target: "looping_reminders",
          partial: "looping_reminders/looping_reminder",
          locals: { looping_reminder: created_reminder }
        )
      end
    end

    context "with :create_loop intent" do
      let(:create_cmd) do
        { intent: :create_loop, params: { interval_minutes: 5, message: "have you done the dishes?", stop_phrase: "doing the dishes" } }
      end
      let(:loop_command) { create_cmd }

      it "creates an active LoopingReminder" do
        expect {
          responder.respond(command: create_cmd, user: user)
        }.to change(LoopingReminder, :count).by(1)
      end

      it "creates the LoopingReminder inside a database transaction" do
        expect(LoopingReminder).to receive(:transaction).and_call_original

        responder.respond(command: create_cmd, user: user)
      end

      it "synthesizes the creation confirmation" do
        responder.respond(command: create_cmd, user: user)

        expect(tts_client).to have_received(:synthesize).with(
          text: "Created looping reminder 1, will ask 'have you done the dishes?' every 5 minutes until you reply 'doing the dishes'",
          voice_id: user.elevenlabs_voice_id
        )
      end

      it "creates the loop as active" do
        responder.respond(command: create_cmd, user: user)

        expect(LoopingReminder.last.active).to be(true)
      end

      it_behaves_like "schedules LoopingReminderJob"
      it_behaves_like "broadcasts loop append"

      it "uses singular 'minute' when interval_minutes is 1" do
        cmd = { intent: :create_loop, params: { interval_minutes: 1, message: "check in", stop_phrase: "done" } }

        responder.respond(command: cmd, user: user)

        expect(tts_client).to have_received(:synthesize).with(
          text: "Created looping reminder 1, will ask 'check in' every 1 minute until you reply 'done'",
          voice_id: user.elevenlabs_voice_id
        )
      end

      context "when stop phrase is already taken" do
        before { create(:looping_reminder, user: user, stop_phrase: "doing the dishes") }

        it "does not create a new LoopingReminder" do
          expect {
            responder.respond(command: create_cmd, user: user)
          }.not_to change(LoopingReminder, :count)
        end

        it "creates a PendingInteraction" do
          expect {
            responder.respond(command: create_cmd, user: user)
          }.to change(PendingInteraction, :count).by(1)
        end

        it "synthesizes the collision response" do
          responder.respond(command: create_cmd, user: user)

          expect(tts_client).to have_received(:synthesize).with(
            text: "Stop phrase already in use. Enter a different stop phrase?",
            voice_id: user.elevenlabs_voice_id
          )
        end

        it "stores interval and message in PendingInteraction context" do
          responder.respond(command: create_cmd, user: user)

          pi = PendingInteraction.last
          expect(pi.context["interval_minutes"]).to eq(5)
          expect(pi.context["message"]).to eq("have you done the dishes?")
        end

        it "sets PendingInteraction to expire in 5 minutes" do
          freeze_time do
            responder.respond(command: create_cmd, user: user)

            expect(PendingInteraction.last.expires_at).to be_within(1.second).of(5.minutes.from_now)
          end
        end
      end

      context "when stop phrase is taken via alias (not stop phrase)" do
        before do
          other_loop = create(:looping_reminder, user: user)
          create(:command_alias, user: user, looping_reminder: other_loop, phrase: "doing the dishes")
        end

        it "creates a PendingInteraction" do
          expect {
            responder.respond(command: create_cmd, user: user)
          }.to change(PendingInteraction, :count).by(1)
        end

        it "synthesizes the collision response" do
          responder.respond(command: create_cmd, user: user)

          expect(tts_client).to have_received(:synthesize).with(
            text: "Stop phrase already in use. Enter a different stop phrase?",
            voice_id: user.elevenlabs_voice_id
          )
        end
      end

      context "when stop phrase matches a stop_phrase case-insensitively" do
        before { create(:looping_reminder, user: user, stop_phrase: "doing the dishes") }

        it "detects collision when stop phrase is uppercase" do
          cmd = { intent: :create_loop, params: { interval_minutes: 5, message: "check", stop_phrase: "DOING THE DISHES" } }

          expect {
            responder.respond(command: cmd, user: user)
          }.to change(PendingInteraction, :count).by(1)
        end
      end

      context "when stop phrase matches an alias case-insensitively" do
        before do
          other_loop = create(:looping_reminder, user: user)
          create(:command_alias, user: user, looping_reminder: other_loop, phrase: "doing the dishes")
        end

        it "detects collision when stop phrase is uppercase" do
          cmd = { intent: :create_loop, params: { interval_minutes: 5, message: "check", stop_phrase: "DOING THE DISHES" } }

          expect {
            responder.respond(command: cmd, user: user)
          }.to change(PendingInteraction, :count).by(1)
        end
      end

      context "when user has an alias with a different phrase" do
        before do
          other_loop = create(:looping_reminder, user: user)
          create(:command_alias, user: user, looping_reminder: other_loop, phrase: "some other phrase")
        end

        it "creates the LoopingReminder without collision" do
          expect {
            responder.respond(command: create_cmd, user: user)
          }.to change(LoopingReminder, :count).by(1)
        end
      end
    end

    context "with :run_loop intent" do
      let!(:reminder) { create(:looping_reminder, user: user, number: 1, active: false) }
      let(:loop_command) { { intent: :run_loop, params: { number: 1 } } }

      it "activates the loop and synthesizes confirmation" do
        responder.respond(command: { intent: :run_loop, params: { number: 1 } }, user: user)

        expect(tts_client).to have_received(:synthesize).with(
          text: "Running looping reminder 1",
          voice_id: user.elevenlabs_voice_id
        )
        expect(reminder.reload.active).to be(true)
      end

      it "schedules LoopingReminderJob with the incremented epoch after activation" do
        freeze_time do
          job_proxy = double("job_proxy", perform_later: nil)
          allow(LoopingReminderJob).to receive(:set).and_return(job_proxy)

          responder.respond(command: { intent: :run_loop, params: { number: 1 } }, user: user)
          new_epoch = reminder.reload.job_epoch

          expect(LoopingReminderJob).to have_received(:set)
            .with(wait_until: reminder.interval_minutes.minutes.from_now)
          expect(job_proxy).to have_received(:perform_later)
            .with(reminder.id, reminder.interval_minutes.minutes.from_now, new_epoch)
        end
      end

      it_behaves_like "broadcasts loop replace"

      context "when loop is already active" do
        before { reminder.activate! }

        it "synthesizes the already-active response" do
          responder.respond(command: { intent: :run_loop, params: { number: 1 } }, user: user)

          expect(tts_client).to have_received(:synthesize).with(
            text: "Loop 1 already active",
            voice_id: user.elevenlabs_voice_id
          )
        end

        it "does not schedule another job" do
          responder.respond(command: { intent: :run_loop, params: { number: 1 } }, user: user)

          expect(LoopingReminderJob).not_to have_received(:set)
        end
      end

      context "when loop is not found" do
        it "synthesizes the not-found response" do
          responder.respond(command: { intent: :run_loop, params: { number: 99 } }, user: user)

          expect(tts_client).to have_received(:synthesize).with(
            text: "Loop 99 not found",
            voice_id: user.elevenlabs_voice_id
          )
        end
      end
    end

    context "with :stop_loop intent" do
      let!(:reminder) { create(:looping_reminder, user: user, active: true) }
      let(:loop_command) { { intent: :stop_loop, params: { looping_reminder_id: reminder.id } } }

      it "stops the loop and synthesizes confirmation" do
        responder.respond(command: { intent: :stop_loop, params: { looping_reminder_id: reminder.id } }, user: user)

        expect(tts_client).to have_received(:synthesize).with(
          text: "Excellent. Stopping looping reminder #{reminder.number}",
          voice_id: user.elevenlabs_voice_id
        )
        expect(reminder.reload.active).to be(false)
      end

      it_behaves_like "broadcasts loop replace"

      context "when looping reminder is not found" do
        it "synthesizes a not-found response" do
          responder.respond(command: { intent: :stop_loop, params: { looping_reminder_id: 0 } }, user: user)

          expect(tts_client).to have_received(:synthesize).with(
            text: "Looping reminder not found",
            voice_id: user.elevenlabs_voice_id
          )
        end

        it "does not broadcast when reminder is not found" do
          responder.respond(command: { intent: :stop_loop, params: { looping_reminder_id: 0 } }, user: user)

          expect(Turbo::StreamsChannel).not_to have_received(:broadcast_replace_to)
        end

        it "handles absent looping_reminder_id key without raising" do
          responder.respond(command: { intent: :stop_loop, params: {} }, user: user)

          expect(tts_client).to have_received(:synthesize).with(
            text: "Looping reminder not found",
            voice_id: user.elevenlabs_voice_id
          )
        end
      end
    end

    context "with :alias_loop intent" do
      let!(:reminder) { create(:looping_reminder, user: user, number: 1) }
      let(:alias_cmd) { { intent: :alias_loop, params: { number: 1, target: "remember the dishes" } } }
      let(:loop_command) { alias_cmd }

      it "creates a CommandAlias and synthesizes confirmation" do
        expect {
          responder.respond(command: alias_cmd, user: user)
        }.to change(CommandAlias, :count).by(1)

        expect(tts_client).to have_received(:synthesize).with(
          text: "Alias 'remember the dishes' created for looping reminder 1",
          voice_id: user.elevenlabs_voice_id
        )
      end

      it "stores the target phrase on the created CommandAlias" do
        responder.respond(command: alias_cmd, user: user)

        expect(CommandAlias.last.phrase).to eq("remember the dishes")
      end

      it_behaves_like "broadcasts loop replace"

      it "broadcasts the reminder with command_aliases preloaded" do
        responder.respond(command: alias_cmd, user: user)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to) do |_, **kwargs|
          expect(kwargs[:locals][:looping_reminder].association(:command_aliases).loaded?).to be(true)
        end
      end

      context "when number is nil" do
        let(:bad_cmd) { { intent: :alias_loop, params: { number: nil, target: "do the thing" } } }

        it "synthesizes the not-found response" do
          responder.respond(command: bad_cmd, user: user)

          expect(tts_client).to have_received(:synthesize).with(
            text: "Loop ? not found",
            voice_id: user.elevenlabs_voice_id
          )
        end

        it "does not create a CommandAlias" do
          expect {
            responder.respond(command: bad_cmd, user: user)
          }.not_to change(CommandAlias, :count)
        end
      end

      context "when number is given but no reminder matches" do
        let(:bad_cmd) { { intent: :alias_loop, params: { number: 99, target: "do the thing" } } }

        it "includes the given number in the not-found message" do
          responder.respond(command: bad_cmd, user: user)

          expect(tts_client).to have_received(:synthesize).with(
            text: "Loop 99 not found",
            voice_id: user.elevenlabs_voice_id
          )
        end
      end

      context "when target phrase is already taken" do
        before { create(:looping_reminder, user: user, stop_phrase: "remember the dishes") }

        it "creates a PendingInteraction" do
          expect {
            responder.respond(command: alias_cmd, user: user)
          }.to change(PendingInteraction, :count).by(1)
        end

        it "synthesizes the alias collision response" do
          responder.respond(command: alias_cmd, user: user)

          expect(tts_client).to have_received(:synthesize).with(
            text: "Alias phrase already in use. Enter a different phrase?",
            voice_id: user.elevenlabs_voice_id
          )
        end

        it "stores looping_reminder_id in PendingInteraction context" do
          responder.respond(command: alias_cmd, user: user)

          pi = PendingInteraction.last
          expect(pi.context["looping_reminder_id"]).to eq(reminder.id)
        end

        it "sets PendingInteraction to expire in 5 minutes" do
          freeze_time do
            responder.respond(command: alias_cmd, user: user)

            expect(PendingInteraction.last.expires_at).to be_within(1.second).of(5.minutes.from_now)
          end
        end
      end
    end

    context "with :give_up intent" do
      it "synthesizes the give-up response" do
        responder.respond(command: { intent: :give_up, params: {} }, user: user)

        expect(tts_client).to have_received(:synthesize).with(
          text: "OK, giving up.",
          voice_id: user.elevenlabs_voice_id
        )
      end
    end

    context "with :unknown intent and replacement_phrase_taken error" do
      it "synthesizes stop phrase collision retry text" do
        cmd = { intent: :unknown, params: { error: :replacement_phrase_taken, kind: "stop_phrase_replacement" } }

        responder.respond(command: cmd, user: user)

        expect(tts_client).to have_received(:synthesize).with(
          text: "Stop phrase also already in use. Try another, or say 'give up' to cancel.",
          voice_id: user.elevenlabs_voice_id
        )
      end

      it "synthesizes alias collision retry text" do
        cmd = { intent: :unknown, params: { error: :replacement_phrase_taken, kind: "alias_phrase_replacement" } }

        responder.respond(command: cmd, user: user)

        expect(tts_client).to have_received(:synthesize).with(
          text: "Alias phrase also already in use. Try another, or say 'give up' to cancel.",
          voice_id: user.elevenlabs_voice_id
        )
      end
    end

    context "with :complete_pending intent (stop_phrase_replacement)" do
      let(:complete_stop_cmd) do
        {
          intent: :complete_pending,
          params: {
            interval_minutes: 5, message: "have you done the dishes?",
            replacement_phrase: "a new stop phrase", kind: "stop_phrase_replacement"
          }
        }
      end
      let(:loop_command) { complete_stop_cmd }

      it "creates a LoopingReminder with the replacement phrase as stop_phrase" do
        expect {
          responder.respond(command: complete_stop_cmd, user: user)
        }.to change(LoopingReminder, :count).by(1)

        expect(LoopingReminder.last.stop_phrase).to eq("a new stop phrase")
      end

      it "creates the LoopingReminder inside a database transaction" do
        expect(LoopingReminder).to receive(:transaction).and_call_original

        responder.respond(command: complete_stop_cmd, user: user)
      end

      it "creates the LoopingReminder as active" do
        responder.respond(command: complete_stop_cmd, user: user)

        expect(LoopingReminder.last.active).to be(true)
      end

      it "synthesizes the creation confirmation with the replacement phrase" do
        responder.respond(command: complete_stop_cmd, user: user)

        expect(tts_client).to have_received(:synthesize).with(
          text: "Created looping reminder 1, will ask 'have you done the dishes?' every 5 minutes until you reply 'a new stop phrase'",
          voice_id: user.elevenlabs_voice_id
        )
      end

      it_behaves_like "schedules LoopingReminderJob"
      it_behaves_like "broadcasts loop append"
    end

    context "with :complete_pending intent (alias_phrase_replacement)" do
      let!(:reminder) { create(:looping_reminder, user: user, number: 2) }
      let(:complete_alias_cmd) do
        {
          intent: :complete_pending,
          params: {
            looping_reminder_id: reminder.id,
            replacement_phrase: "new alias phrase", kind: "alias_phrase_replacement"
          }
        }
      end
      let(:loop_command) { complete_alias_cmd }

      it "creates a CommandAlias with the replacement phrase" do
        expect {
          responder.respond(command: complete_alias_cmd, user: user)
        }.to change(CommandAlias, :count).by(1)

        expect(CommandAlias.last.phrase).to eq("new alias phrase")
      end

      it "synthesizes the alias confirmation" do
        responder.respond(command: complete_alias_cmd, user: user)

        expect(tts_client).to have_received(:synthesize).with(
          text: "Alias 'new alias phrase' created for looping reminder 2",
          voice_id: user.elevenlabs_voice_id
        )
      end

      it_behaves_like "broadcasts loop replace"
    end
  end
end
