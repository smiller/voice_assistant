class User < ApplicationRecord
  has_secure_password

  after_initialize do
    self.elevenlabs_voice_id ||= ENV["ELEVENLABS_VOICE_ID"]
    self.timezone ||= "Eastern Time (US & Canada)"
  end

  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
end
