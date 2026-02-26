class CommandAlias < ApplicationRecord
  belongs_to :looping_reminder
  belongs_to :user

  validates :phrase, presence: true,
                     length: { maximum: 100 },
                     uniqueness: { scope: :user_id, case_sensitive: false }
end
