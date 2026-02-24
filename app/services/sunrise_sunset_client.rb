require "net/http"
require "json"
require "time"

class SunriseSunsetClient
  Error = Class.new(StandardError)

  BASE_URL = "https://api.sunrise-sunset.org/json"

  def sunset_time(lat:, lng:)
    Rails.cache.fetch("sunset/#{lat}/#{lng}/#{Date.today}", expires_in: 24.hours) do
      data = fetch(lat:, lng:)
      raise Error unless data["status"] == "OK"

      Time.parse(data["results"]["sunset"])
    end
  rescue Error
    raise
  rescue StandardError
    raise Error
  end

  private

  def fetch(lat:, lng:)
    uri = URI(BASE_URL)
    uri.query = URI.encode_www_form(lat: lat, lng: lng, formatted: 0)
    response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) { |http| http.get(uri.request_uri) }
    raise Error, "HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body)
  rescue JSON::ParserError => e
    raise Error, "Invalid response: #{e.message}"
  end
end
