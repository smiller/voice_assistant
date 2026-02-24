require "net/http"
require "json"

class DeepgramClient
  Error = Class.new(StandardError)

  BASE_URL = "https://api.deepgram.com/v1/listen"

  def transcribe(audio:)
    uri = URI(BASE_URL)
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Token #{ENV.fetch("DEEPGRAM_API_KEY")}"
    req["Content-Type"] = "audio/webm"
    req.body = audio
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }
    raise Error unless response.is_a?(Net::HTTPSuccess)

    data = JSON.parse(response.body)
    data.dig("results", "channels", 0, "alternatives", 0, "transcript")
  rescue StandardError
    raise Error
  end
end
