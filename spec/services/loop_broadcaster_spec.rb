require "rails_helper"

RSpec.describe LoopBroadcaster do
  subject(:broadcaster) { described_class.new }

  let(:user) { create(:user) }
  let(:reminder) { create(:looping_reminder, user: user) }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_before_to)
  end

  describe "#replace" do
    it "broadcasts replace to the user channel targeting the reminder's dom_id" do
      broadcaster.replace(user, reminder)

      expect(Turbo::StreamsChannel).to have_received(:broadcast_replace_to).with(
        user,
        target: "looping_reminder_#{reminder.id}",
        partial: "looping_reminders/looping_reminder",
        locals: { looping_reminder: reminder }
      )
    end

    it "does not trigger an extra DB query to reload the reminder" do
      preloaded = reminder
      query_count = 0
      counter = ActiveSupport::Notifications.subscribe("sql.active_record") { query_count += 1 }

      broadcaster.replace(user, preloaded)

      ActiveSupport::Notifications.unsubscribe(counter)
      expect(query_count).to eq(0)
    end
  end

  describe "#append" do
    context "when no higher-numbered reminder exists" do
      it "broadcasts append to the looping_reminders list" do
        broadcaster.append(reminder)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_append_to).with(
          user,
          target: "looping_reminders",
          partial: "looping_reminders/looping_reminder",
          locals: { looping_reminder: reminder }
        )
      end
    end

    context "when multiple higher-numbered reminders exist" do
      # Create further (higher number) first so insertion order != number order.
      # Without .order(:number) the DB would return further first (insertion order),
      # killing the mutant that removes or noops the order clause.
      let!(:further) { create(:looping_reminder, user: user, number: reminder.number + 5) }
      let!(:next_up) { create(:looping_reminder, user: user, number: reminder.number + 1) }

      it "broadcasts before the immediately next higher reminder, not a farther one" do
        broadcaster.append(reminder)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_before_to).with(
          user,
          target: "looping_reminder_#{next_up.id}",
          partial: "looping_reminders/looping_reminder",
          locals: { looping_reminder: reminder }
        )
      end
    end

    context "when a higher-numbered reminder exists" do
      let!(:higher) { create(:looping_reminder, user: user, number: reminder.number + 1) }

      it "broadcasts before the higher-numbered sibling" do
        broadcaster.append(reminder)

        expect(Turbo::StreamsChannel).to have_received(:broadcast_before_to).with(
          user,
          target: "looping_reminder_#{higher.id}",
          partial: "looping_reminders/looping_reminder",
          locals: { looping_reminder: reminder }
        )
      end

      it "does not broadcast_append_to when inserting before a sibling" do
        broadcaster.append(reminder)

        expect(Turbo::StreamsChannel).not_to have_received(:broadcast_append_to)
      end
    end
  end
end
