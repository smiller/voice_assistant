require "rails_helper"

RSpec.describe DeepgramClient do
  subject(:client) { described_class.new }

  let(:audio) { "\x00\x01\x02\x03" }
  let(:api_url) { "https://api.deepgram.com/v1/listen" }

  describe "#transcribe" do
    context "when the API responds successfully" do
      before do
        ENV["DEEPGRAM_API_KEY"] = "test_dg_key"
        stub_request(:post, api_url)
          .with(
            headers: { "Authorization" => "Token test_dg_key", "Content-Type" => "audio/webm" },
            body: audio
          )
          .to_return(
            status: 200,
            body: JSON.generate({
              results: {
                channels: [
                  { alternatives: [
                    { transcript: "set a timer for five minutes" },
                    { transcript: "wrong alternative" }
                  ] },
                  { alternatives: [ { transcript: "wrong channel" } ] }
                ]
              }
            }),
            headers: { "Content-Type" => "application/json" }
          )
      end

      after { ENV.delete("DEEPGRAM_API_KEY") }

      it "returns the transcript string" do
        result = client.transcribe(audio: audio)

        expect(result).to eq("set a timer for five minutes")
      end
    end

    context "when the API returns an error status" do
      before do
        stub_request(:post, api_url)
          .to_return(
            status: 401,
            body: JSON.generate({ err_code: "INVALID_CREDENTIALS", err_msg: "Invalid credentials." }),
            headers: { "Content-Type" => "application/json" }
          )
      end

      it "raises an error" do
        expect { client.transcribe(audio: audio) }
          .to raise_error(DeepgramClient::Error)
      end
    end

    context "when the network request fails" do
      before do
        stub_request(:post, api_url)
          .to_raise(Net::OpenTimeout)
      end

      it "raises an error" do
        expect { client.transcribe(audio: audio) }
          .to raise_error(DeepgramClient::Error)
      end
    end
  end
end
