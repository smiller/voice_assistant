require "rails_helper"

RSpec.describe LoopBroadcaster do
  subject(:broadcaster) { described_class.new }

  let(:user) { create(:user) }
  let(:reminder) { create(:looping_reminder, user: user) }

  before do
    allow(Turbo::StreamsChannel).to receive(:broadcast_replace_to)
    allow(Turbo::StreamsChannel).to receive(:broadcast_append_to)
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
end
