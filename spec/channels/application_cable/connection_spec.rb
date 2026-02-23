require "rails_helper"

RSpec.describe ApplicationCable::Connection, type: :channel do
  let(:user) { create(:user) }

  it "rejects connection when session has no user_id" do
    expect { connect "/cable" }.to have_rejected_connection
  end

  it "rejects connection when user_id does not match any user" do
    expect { connect "/cable", session: { user_id: 0 } }.to have_rejected_connection
  end

  it "accepts connection and identifies current_user" do
    connect "/cable", session: { user_id: user.id }

    expect(connection.current_user).to eq(user)
  end
end
