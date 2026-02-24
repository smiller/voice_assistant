require "rails_helper"

RSpec.describe ElevenLabsClient do
  subject(:client) { described_class.new }

  let(:text) { "The time is 2:11 PM" }
  let(:voice_id) { "abc123" }
  let(:api_url) { "https://api.elevenlabs.io/v1/text-to-speech/#{voice_id}" }
  let(:audio_bytes) { "\xFF\xFB\x90\x00" }

  before { ENV["ELEVENLABS_API_KEY"] = "test_api_key" }
  after  { ENV.delete("ELEVENLABS_API_KEY") }

  describe "#synthesize" do
    context "when the API responds successfully" do
      before do
        stub_request(:post, api_url)
          .with(
            headers: {
              "xi-api-key" => "test_api_key",
              "Content-Type" => "application/json",
              "Accept" => "audio/mpeg"
            },
            body: { text: text, model_id: ElevenLabsClient::MODEL_ID }.to_json
          )
          .to_return(status: 200, body: audio_bytes, headers: { "Content-Type" => "audio/mpeg" })
      end

      it "returns audio bytes" do
        result = client.synthesize(text: text, voice_id: voice_id)

        expect(result).to eq(audio_bytes)
      end
    end

    context "when the API returns an error status" do
      before do
        stub_request(:post, api_url)
          .to_return(status: 401, body: "Unauthorized", headers: {})
      end

      it "raises an error" do
        expect { client.synthesize(text: text, voice_id: voice_id) }
          .to raise_error(ElevenLabsClient::Error)
      end
    end

    context "when the network request fails" do
      before do
        stub_request(:post, api_url)
          .to_raise(Net::OpenTimeout)
      end

      it "raises an error" do
        expect { client.synthesize(text: text, voice_id: voice_id) }
          .to raise_error(ElevenLabsClient::Error)
      end
    end
  end
end
