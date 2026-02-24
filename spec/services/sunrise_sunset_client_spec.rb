require "rails_helper"

RSpec.describe SunriseSunsetClient do
  subject(:client) { described_class.new }

  let(:lat) { 40.7128 }
  let(:lng) { -74.0060 }
  let(:api_url) { "https://api.sunrise-sunset.org/json" }

  describe "#sunset_time" do
    context "when the API responds successfully" do
      before do
        stub_request(:get, api_url)
          .with(query: hash_including("lat" => lat.to_s, "lng" => lng.to_s, "formatted" => "0"))
          .to_return(
            status: 200,
            body: JSON.generate({
              results: { sunset: "2026-02-23T22:35:00+00:00" },
              status: "OK"
            }),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "returns a Time object" do
        result = client.sunset_time(lat: lat, lng: lng)

        expect(result).to be_a(Time)
      end

      it "returns the correct sunset time" do
        result = client.sunset_time(lat: lat, lng: lng)

        expect(result).to eq(Time.parse("2026-02-23T22:35:00+00:00"))
      end
    end

    context "when the API returns an error status" do
      before do
        stub_request(:get, api_url)
          .with(query: hash_including({}))
          .to_return(
            status: 200,
            body: JSON.generate({ results: { sunset: "2026-02-23T22:35:00+00:00" }, status: "INVALID_REQUEST" }),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises an error" do
        expect { client.sunset_time(lat: lat, lng: lng) }
          .to raise_error(SunriseSunsetClient::Error)
      end
    end

    context "when the API returns a non-2xx HTTP response" do
      before do
        stub_request(:get, api_url)
          .with(query: hash_including({}))
          .to_return(status: 503, body: "Service Unavailable")
      end

      it "raises an error mentioning the HTTP status code" do
        expect { client.sunset_time(lat: lat, lng: lng) }
          .to raise_error(SunriseSunsetClient::Error, /503/)
      end
    end

    context "when the API returns a non-JSON body" do
      before do
        stub_request(:get, api_url)
          .with(query: hash_including({}))
          .to_return(status: 200, body: "<html>error</html>", headers: { "Content-Type" => "text/html" })
      end

      it "raises an error mentioning 'Invalid response'" do
        expect { client.sunset_time(lat: lat, lng: lng) }
          .to raise_error(SunriseSunsetClient::Error, /Invalid response/)
      end
    end

    context "when the network request fails" do
      before do
        stub_request(:get, api_url)
          .with(query: hash_including({}))
          .to_raise(Net::OpenTimeout)
      end

      it "raises an error" do
        expect { client.sunset_time(lat: lat, lng: lng) }
          .to raise_error(SunriseSunsetClient::Error)
      end
    end
  end
end
