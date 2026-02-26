class User < ApplicationRecord
  has_secure_password

  attr_reader :api_token

  before_create :generate_api_token
  has_many :reminders, dependent: :destroy
  has_many :looping_reminders, dependent: :destroy
  has_many :command_aliases, dependent: :destroy
  has_many :pending_interactions, dependent: :destroy

  after_initialize :set_defaults, if: :new_record?

  def phrase_taken?(phrase)
    looping_reminders.where("LOWER(stop_phrase) = ?", phrase.downcase).exists? ||
      command_aliases.where("LOWER(phrase) = ?", phrase.downcase).exists?
  end

  def authenticate_api_token(token)
    ActiveSupport::SecurityUtils.secure_compare(
      api_token_digest.to_s,
      self.class.digest_api_token(token)
    )
  end

  def regenerate_api_token
    raw = SecureRandom.base58(24)
    update!(api_token_digest: self.class.digest_api_token(raw))
    @api_token = raw
  end

  def self.find_by_api_token(token)
    find_by(api_token_digest: digest_api_token(token))
  end

  def self.digest_api_token(token)
    OpenSSL::Digest::SHA256.hexdigest(token)
  end

  private

  def set_defaults
    self.elevenlabs_voice_id ||= ENV["ELEVENLABS_VOICE_ID"]
    self.timezone ||= "Eastern Time (US & Canada)"
  end

  def generate_api_token
    raw = SecureRandom.base58(24)
    self.api_token_digest = self.class.digest_api_token(raw)
    @api_token = raw
  end

  validates :email, presence: true,
                    uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :lat, numericality: { greater_than_or_equal_to: -90, less_than_or_equal_to: 90 }, allow_nil: true
  validates :lng, numericality: { greater_than_or_equal_to: -180, less_than_or_equal_to: 180 }, allow_nil: true
end
