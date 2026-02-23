require "net/http"
require "json"

class ElevenLabsClient
  Error = Class.new(StandardError)

  BASE_URL = "https://api.elevenlabs.io/v1/text-to-speech"

  def synthesize(text:, voice_id:)
    uri = URI("#{BASE_URL}/#{voice_id}")
    req = Net::HTTP::Post.new(uri)
    req["xi-api-key"] = ENV["ELEVENLABS_API_KEY"]
    req["Content-Type"] = "application/json"
    req["Accept"] = "audio/mpeg"
    req.body = { text: text, model_id: "eleven_multilingual_v2" }.to_json
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    raise Error unless response.is_a?(Net::HTTPSuccess)

    response.body
  rescue Error
    raise
  rescue StandardError
    raise Error
  end
end
