class User < ApplicationRecord
  has_secure_password

  after_initialize :set_defaults, if: :new_record?

  private

  def set_defaults
    self.elevenlabs_voice_id ||= ENV["ELEVENLABS_VOICE_ID"]
    self.timezone ||= "Eastern Time (US & Canada)"
  end

  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :lat, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :lng, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
end
