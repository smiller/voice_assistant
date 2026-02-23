require "net/http"
require "json"
require "time"

class SunriseSunsetClient
  Error = Class.new(StandardError)

  BASE_URL = "https://api.sunrise-sunset.org/json"

  def sunset_time(lat:, lng:)
    data = fetch(lat:, lng:)
    raise Error unless data["status"] == "OK"

    Time.parse(data["results"]["sunset"])
  rescue Error
    raise
  rescue StandardError
    raise Error
  end

  private

  def fetch(lat:, lng:)
    uri = URI(BASE_URL)
    uri.query = URI.encode_www_form(lat: lat, lng: lng, formatted: 0)
    response = Net::HTTP.get_response(uri)
    JSON.parse(response.body)
  end
end
