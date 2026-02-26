class PendingInteraction < ApplicationRecord
  belongs_to :user

  INTERACTION_TTL = 5.minutes
  KINDS = %w[stop_phrase_replacement alias_phrase_replacement].freeze
  validates :kind, inclusion: { in: KINDS }
  validates :expires_at, presence: true

  scope :active, -> { where("expires_at > ?", Time.current) }

  def self.for(user)
    where(user: user).active.order(created_at: :asc).first
  end
end
