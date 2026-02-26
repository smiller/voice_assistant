require "rails_helper"

RSpec.describe LoopingReminderDispatcher do
  subject(:dispatcher) { described_class.new }

  let(:user) { create(:user) }

  describe "#dispatch" do
    context "with no pending interaction, no stop phrase match, no alias match" do
      it "delegates to CommandParser" do
        result = dispatcher.dispatch(transcript: "what time is it", user: user)

        expect(result[:intent]).to eq(:time_check)
      end
    end

    context "stop phrase matching" do
      it "returns :stop_loop when transcript contains an active loop's stop phrase" do
        reminder = create(:looping_reminder, user: user, stop_phrase: "doing the dishes", active: true)

        result = dispatcher.dispatch(transcript: "I am doing the dishes now", user: user)

        expect(result[:intent]).to eq(:stop_loop)
        expect(result[:params][:looping_reminder_id]).to eq(reminder.id)
      end

      it "is case-insensitive on the transcript side" do
        reminder = create(:looping_reminder, user: user, stop_phrase: "doing the dishes", active: true)

        result = dispatcher.dispatch(transcript: "DOING THE DISHES", user: user)

        expect(result[:intent]).to eq(:stop_loop)
        expect(result[:params][:looping_reminder_id]).to eq(reminder.id)
      end

      it "is case-insensitive on the stop phrase side" do
        reminder = create(:looping_reminder, user: user, stop_phrase: "Doing The Dishes", active: true)

        result = dispatcher.dispatch(transcript: "doing the dishes", user: user)

        expect(result[:intent]).to eq(:stop_loop)
        expect(result[:params][:looping_reminder_id]).to eq(reminder.id)
      end

      it "does not match when transcript does not contain the stop phrase" do
        create(:looping_reminder, user: user, stop_phrase: "doing the dishes", active: true)

        result = dispatcher.dispatch(transcript: "what time is it", user: user)

        expect(result[:intent]).not_to eq(:stop_loop)
      end

      it "does not match inactive loops" do
        create(:looping_reminder, user: user, stop_phrase: "doing the dishes", active: false)

        result = dispatcher.dispatch(transcript: "doing the dishes", user: user)

        expect(result[:intent]).not_to eq(:stop_loop)
      end

      it "does not match another user's loops" do
        other_user = create(:user)
        create(:looping_reminder, user: other_user, stop_phrase: "doing the dishes", active: true)

        result = dispatcher.dispatch(transcript: "doing the dishes", user: user)

        expect(result[:intent]).not_to eq(:stop_loop)
      end
    end

    context "alias matching" do
      it "returns :run_loop when transcript exactly matches an alias phrase" do
        reminder = create(:looping_reminder, user: user, number: 2)
        create(:command_alias, user: user, looping_reminder: reminder, phrase: "remember the dishes")

        result = dispatcher.dispatch(transcript: "remember the dishes", user: user)

        expect(result[:intent]).to eq(:run_loop)
        expect(result[:params][:number]).to eq(2)
      end

      it "is case-insensitive for alias matching" do
        reminder = create(:looping_reminder, user: user, number: 1)
        create(:command_alias, user: user, looping_reminder: reminder, phrase: "Remember The Dishes")

        result = dispatcher.dispatch(transcript: "remember the dishes", user: user)

        expect(result[:intent]).to eq(:run_loop)
      end

      it "strips whitespace from the transcript before matching" do
        reminder = create(:looping_reminder, user: user, number: 1)
        create(:command_alias, user: user, looping_reminder: reminder, phrase: "remember the dishes")

        result = dispatcher.dispatch(transcript: "  remember the dishes  ", user: user)

        expect(result[:intent]).to eq(:run_loop)
      end

      it "does not match aliases with extra words" do
        reminder = create(:looping_reminder, user: user, number: 1)
        create(:command_alias, user: user, looping_reminder: reminder, phrase: "remember the dishes")

        result = dispatcher.dispatch(transcript: "please remember the dishes", user: user)

        expect(result[:intent]).not_to eq(:run_loop)
      end
    end

    context "stop phrase takes priority over alias" do
      it "returns :stop_loop when transcript matches both a stop phrase and an alias" do
        active_reminder = create(:looping_reminder, user: user, stop_phrase: "do the dishes", active: true)
        other_reminder  = create(:looping_reminder, user: user)
        create(:command_alias, user: user, looping_reminder: other_reminder, phrase: "do the dishes")

        result = dispatcher.dispatch(transcript: "do the dishes", user: user)

        expect(result[:intent]).to eq(:stop_loop)
        expect(result[:params][:looping_reminder_id]).to eq(active_reminder.id)
      end
    end

    context "expired PendingInteraction cleanup" do
      it "destroys expired interactions before dispatching" do
        create(:pending_interaction, user: user, expires_at: 1.minute.ago)

        expect { dispatcher.dispatch(transcript: "what time is it", user: user) }
          .to change(PendingInteraction, :count).by(-1)
      end
    end

    context "with an active PendingInteraction (multi-turn)" do
      let!(:pending) do
        create(:pending_interaction,
               user: user,
               kind: "stop_phrase_replacement",
               context: { interval_minutes: 5, message: "do the thing", original_stop_phrase: "doing it" },
               expires_at: 5.minutes.from_now)
      end

      it "returns :give_up when user says 'give up'" do
        result = dispatcher.dispatch(transcript: "give up", user: user)

        expect(result[:intent]).to eq(:give_up)
        expect(result[:params]).to eq({})
      end

      it "destroys the PendingInteraction on give up" do
        expect { dispatcher.dispatch(transcript: "give up", user: user) }
          .to change(PendingInteraction, :count).by(-1)
      end

      it "returns :give_up case-insensitively" do
        result = dispatcher.dispatch(transcript: "Give Up", user: user)

        expect(result[:intent]).to eq(:give_up)
      end

      it "returns replacement_phrase_taken error when replacement phrase matches an existing stop phrase" do
        create(:looping_reminder, user: user, stop_phrase: "taken phrase")

        result = dispatcher.dispatch(transcript: "taken phrase", user: user)

        expect(result[:intent]).to eq(:unknown)
        expect(result[:params][:error]).to eq(:replacement_phrase_taken)
        expect(result[:params][:kind]).to eq("stop_phrase_replacement")
      end

      it "returns replacement_phrase_taken error when replacement phrase matches an existing alias" do
        reminder = create(:looping_reminder, user: user)
        create(:command_alias, user: user, looping_reminder: reminder, phrase: "taken alias")

        result = dispatcher.dispatch(transcript: "taken alias", user: user)

        expect(result[:intent]).to eq(:unknown)
        expect(result[:params][:error]).to eq(:replacement_phrase_taken)
      end

      it "strips whitespace from transcript before completing pending interaction" do
        result = dispatcher.dispatch(transcript: "  a brand new phrase  ", user: user)

        expect(result[:intent]).to eq(:complete_pending)
        expect(result[:params][:replacement_phrase]).to eq("a brand new phrase")
      end

      it "refreshes the TTL to 5 minutes from now when replacement phrase is taken" do
        # Override expires_at so it differs from 5.minutes.from_now
        pending.update!(expires_at: 1.minute.from_now)
        create(:looping_reminder, user: user, stop_phrase: "taken phrase")

        freeze_time do
          dispatcher.dispatch(transcript: "taken phrase", user: user)

          expect(pending.reload.expires_at).to be_within(1.second).of(5.minutes.from_now)
        end
      end

      it "returns :complete_pending with replacement phrase when phrase is free" do
        result = dispatcher.dispatch(transcript: "a brand new phrase", user: user)

        expect(result[:intent]).to eq(:complete_pending)
        expect(result[:params][:replacement_phrase]).to eq("a brand new phrase")
        expect(result[:params][:kind]).to eq("stop_phrase_replacement")
      end

      it "does not block a free phrase when user has loops with different stop phrases" do
        create(:looping_reminder, user: user, stop_phrase: "some other phrase")

        result = dispatcher.dispatch(transcript: "a brand new phrase", user: user)

        expect(result[:intent]).to eq(:complete_pending)
      end

      it "blocks a replacement phrase that matches an existing stop phrase case-insensitively" do
        create(:looping_reminder, user: user, stop_phrase: "taken phrase")

        result = dispatcher.dispatch(transcript: "TAKEN PHRASE", user: user)

        expect(result[:params][:error]).to eq(:replacement_phrase_taken)
      end

      it "blocks a replacement phrase that matches an existing alias phrase case-insensitively" do
        reminder = create(:looping_reminder, user: user)
        create(:command_alias, user: user, looping_reminder: reminder, phrase: "taken alias")

        result = dispatcher.dispatch(transcript: "TAKEN ALIAS", user: user)

        expect(result[:params][:error]).to eq(:replacement_phrase_taken)
      end

      it "does not block a free phrase when user has aliases with different phrases" do
        reminder = create(:looping_reminder, user: user)
        create(:command_alias, user: user, looping_reminder: reminder, phrase: "some other alias")

        result = dispatcher.dispatch(transcript: "a brand new phrase", user: user)

        expect(result[:intent]).to eq(:complete_pending)
      end

      it "destroys the PendingInteraction on successful completion" do
        expect { dispatcher.dispatch(transcript: "a brand new phrase", user: user) }
          .to change(PendingInteraction, :count).by(-1)
      end

      it "carries the original context through on completion" do
        result = dispatcher.dispatch(transcript: "a brand new phrase", user: user)

        expect(result[:params][:interval_minutes]).to eq(5)
        expect(result[:params][:message]).to eq("do the thing")
      end
    end
  end
end
