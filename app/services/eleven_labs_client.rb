require "net/http"
require "json"

class ElevenLabsClient
  Error = Class.new(StandardError)

  BASE_URL = "https://api.elevenlabs.io/v1/text-to-speech"
  MODEL_ID = "eleven_multilingual_v2"

  def synthesize(text:, voice_id:)
    uri = URI("#{BASE_URL}/#{voice_id}")
    req = Net::HTTP::Post.new(uri)
    req["xi-api-key"] = ENV.fetch("ELEVENLABS_API_KEY")
    req["Content-Type"] = "application/json"
    req["Accept"] = "audio/mpeg"
    req.body = { text: text, model_id: MODEL_ID }.to_json
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error("ElevenLabsClient error: #{response.code} #{response.body}")
      raise Error
    end

    response.body
  rescue Error
    raise
  rescue StandardError => e
    Rails.logger.error("ElevenLabsClient error: #{e.class}: #{e.message}")
    raise Error
  end
end
