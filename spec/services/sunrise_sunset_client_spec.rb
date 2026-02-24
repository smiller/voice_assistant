require "rails_helper"

RSpec.describe SunriseSunsetClient do
  subject(:client) { described_class.new }

  let(:lat) { 40.7128 }
  let(:lng) { -74.0060 }
  let(:api_url) { "https://api.sunrise-sunset.org/json" }

  describe "#sunset_time" do
    context "when the API responds successfully" do
      before do
        allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache::MemoryStore.new)
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

      it "caches the result and makes only one HTTP request on repeated calls" do
        client.sunset_time(lat: lat, lng: lng)
        client.sunset_time(lat: lat, lng: lng)

        expect(a_request(:get, api_url).with(query: hash_including({}))).to have_been_made.once
      end

      it "uses a separate cache entry for a different latitude" do
        stub_request(:get, api_url)
          .with(query: hash_including("lat" => "51.5074", "lng" => lng.to_s, "formatted" => "0"))
          .to_return(status: 200, body: JSON.generate({ results: { sunset: "2026-02-23T17:00:00+00:00" }, status: "OK" }),
                     headers: { "Content-Type" => "application/json" })

        client.sunset_time(lat: lat, lng: lng)
        client.sunset_time(lat: 51.5074, lng: lng)

        expect(a_request(:get, api_url).with(query: hash_including({}))).to have_been_made.twice
      end

      it "uses a separate cache entry for a different longitude" do
        stub_request(:get, api_url)
          .with(query: hash_including("lat" => lat.to_s, "lng" => "0.1276", "formatted" => "0"))
          .to_return(status: 200, body: JSON.generate({ results: { sunset: "2026-02-23T17:00:00+00:00" }, status: "OK" }),
                     headers: { "Content-Type" => "application/json" })

        client.sunset_time(lat: lat, lng: lng)
        client.sunset_time(lat: lat, lng: 0.1276)

        expect(a_request(:get, api_url).with(query: hash_including({}))).to have_been_made.twice
      end

      it "caches with a 24-hour expiry" do
        cache = ActiveSupport::Cache::MemoryStore.new
        allow(Rails).to receive(:cache).and_return(cache)
        allow(cache).to receive(:fetch).and_call_original

        client.sunset_time(lat: lat, lng: lng)

        expect(cache).to have_received(:fetch)
          .with(a_string_including(lat.to_s, lng.to_s), expires_in: 24.hours)
      end

      it "uses a separate cache entry for a different date" do
        cache = ActiveSupport::Cache::MemoryStore.new
        allow(Rails).to receive(:cache).and_return(cache)

        travel_to Date.new(2026, 2, 23) do
          client.sunset_time(lat: lat, lng: lng)
        end
        travel_to Date.new(2026, 2, 24) do
          client.sunset_time(lat: lat, lng: lng)
        end

        expect(a_request(:get, api_url).with(query: hash_including({}))).to have_been_made.twice
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
