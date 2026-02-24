require "net/http"
require "json"

class DeepgramClient
  Error = Class.new(StandardError)

  BASE_URL = "https://api.deepgram.com/v1/listen"

  def transcribe(audio:)
    uri = URI(BASE_URL)
    req = Net::HTTP::Post.new(uri)
    req["Authorization"] = "Token #{ENV.fetch("DEEPGRAM_API_KEY")}"
    req["Content-Type"] = "audio/webm;codecs=opus"
    req.body = audio
    Rails.logger.info("DeepgramClient: sending #{audio.bytesize} bytes")
    response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) { |http| http.request(req) }

    unless response.is_a?(Net::HTTPSuccess)
      Rails.logger.error("DeepgramClient error: #{response.code} #{response.body}")
      raise Error
    end

    data = JSON.parse(response.body)
    data.dig("results", "channels", 0, "alternatives", 0, "transcript")
  rescue Error
    raise
  rescue StandardError => e
    Rails.logger.error("DeepgramClient error: #{e.class}: #{e.message}")
    raise Error
  end
end
