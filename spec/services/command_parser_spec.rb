require "rails_helper"

RSpec.describe CommandParser do
  subject(:parser) { described_class.new }

  describe "#parse" do
    context "with an empty string" do
      it "returns unknown intent" do
        result = parser.parse("")

        expect(result[:intent]).to eq(:unknown)
      end
    end

    context "with 'time check'" do
      it "returns :time_check intent with empty params" do
        result = parser.parse("time check")

        expect(result[:intent]).to eq(:time_check)
        expect(result[:params]).to eq({})
      end
    end

    context "with 'sunset'" do
      it "returns :sunset intent with empty params" do
        result = parser.parse("sunset")

        expect(result[:intent]).to eq(:sunset)
        expect(result[:params]).to eq({})
      end
    end

    context "with mixed-case input" do
      it "matches case-insensitively" do
        expect(parser.parse("Time Check")[:intent]).to eq(:time_check)
        expect(parser.parse("SUNSET")[:intent]).to eq(:sunset)
      end
    end

    context "with 'set timer for 5 minutes'" do
      it "returns :timer intent with minutes param" do
        result = parser.parse("set timer for 5 minutes")

        expect(result[:intent]).to eq(:timer)
        expect(result[:params][:minutes]).to eq(5)
      end
    end

    context "with spoken number words" do
      it "converts 'ten' to 10 for timer" do
        result = parser.parse("set timer for ten minutes")

        expect(result[:intent]).to eq(:timer)
        expect(result[:params][:minutes]).to eq(10)
      end
    end

    context "with 'timer 10 minutes' (no 'for')" do
      it "still matches the timer intent" do
        result = parser.parse("timer 10 minutes")

        expect(result[:intent]).to eq(:timer)
        expect(result[:params][:minutes]).to eq(10)
      end
    end

    context "with uppercase TIMER" do
      it "matches case-insensitively" do
        result = parser.parse("TIMER 5 MINUTES")

        expect(result[:intent]).to eq(:timer)
        expect(result[:params][:minutes]).to eq(5)
      end
    end

    context "with 'set 7am reminder to write morning pages'" do
      it "returns :reminder intent with parsed hour, minute, and message" do
        result = parser.parse("set 7am reminder to write morning pages")

        expect(result[:intent]).to eq(:reminder)
        expect(result[:params][:hour]).to eq(7)
        expect(result[:params][:minute]).to eq(0)
        expect(result[:params][:message]).to eq("write morning pages")
      end
    end

    context "with 'set seven thirty am reminder to do yoga' (spoken word form)" do
      it "parses minutes correctly" do
        result = parser.parse("set seven thirty am reminder to do yoga")

        expect(result[:intent]).to eq(:reminder)
        expect(result[:params][:hour]).to eq(7)
        expect(result[:params][:minute]).to eq(30)
        expect(result[:params][:message]).to eq("do yoga")
      end
    end

    context "with 'set 9pm reminder to take medication'" do
      it "converts pm hour to 24-hour format" do
        result = parser.parse("set 9pm reminder to take medication")

        expect(result[:intent]).to eq(:reminder)
        expect(result[:params][:hour]).to eq(21)
      end
    end

    context "with 'set daily 7am reminder to write morning pages'" do
      it "returns :daily_reminder intent with parsed params" do
        result = parser.parse("set daily 7am reminder to write morning pages")

        expect(result[:intent]).to eq(:daily_reminder)
        expect(result[:params][:hour]).to eq(7)
        expect(result[:params][:minute]).to eq(0)
        expect(result[:params][:message]).to eq("write morning pages")
      end
    end

    context "with unrecognized input" do
      it "returns :unknown intent with empty params" do
        result = parser.parse("blah blah blah")

        expect(result[:intent]).to eq(:unknown)
        expect(result[:params]).to eq({})
      end
    end

    context "with 12pm (noon)" do
      it "keeps hour as 12" do
        result = parser.parse("set 12pm reminder to eat lunch")

        expect(result[:params][:hour]).to eq(12)
      end
    end

    context "with 12am (midnight)" do
      it "converts hour to 0" do
        result = parser.parse("set 12am reminder to sleep")

        expect(result[:params][:hour]).to eq(0)
      end
    end

    context "with the same number word appearing twice in a transcript" do
      it "replaces all occurrences" do
        result = parser.parse("set daily ten am reminder to do ten pushups")

        expect(result[:params][:message]).to eq("do 10 pushups")
      end
    end

    context "when number normalization applies to both the time and the message" do
      it "collapses all oh-prefix digits, including those in the message" do
        result = parser.parse("set a seven oh five pm reminder to take oh nine pills")

        expect(result[:params][:hour]).to eq(19)
        expect(result[:params][:minute]).to eq(5)
        expect(result[:params][:message]).to eq("take 09 pills")
      end

      it "collapses all tens+ones pairs, including those in the message" do
        # time: "four forty two pm" → 4:42 PM; message: "thirty six" must also collapse
        result = parser.parse("set a four forty two pm reminder to do thirty six pushups")

        expect(result[:params][:hour]).to eq(16)
        expect(result[:params][:minute]).to eq(42)
        expect(result[:params][:message]).to eq("do 36 pushups")
      end
    end

    context "with multiple consecutive spaces (extra whitespace in transcript)" do
      it "matches timer with two spaces after 'timer'" do
        result = parser.parse("timer  5 minutes")

        expect(result[:intent]).to eq(:timer)
        expect(result[:params][:minutes]).to eq(5)
      end

      it "matches timer with two spaces after 'for'" do
        result = parser.parse("timer for  5 minutes")

        expect(result[:intent]).to eq(:timer)
        expect(result[:params][:minutes]).to eq(5)
      end

      it "matches timer with two spaces before 'minutes'" do
        result = parser.parse("timer for 5  minutes")

        expect(result[:intent]).to eq(:timer)
        expect(result[:params][:minutes]).to eq(5)
      end
    end

    context "with an uppercase number word" do
      it "normalizes case-insensitively" do
        result = parser.parse("set timer for TEN minutes")

        expect(result[:intent]).to eq(:timer)
        expect(result[:params][:minutes]).to eq(10)
      end
    end

    context "with uppercase PM" do
      it "still converts to 24-hour format" do
        result = parser.parse("set 7PM reminder to eat dinner")

        expect(result[:intent]).to eq(:reminder)
        expect(result[:params][:hour]).to eq(19)
      end
    end

    context "with 'set a six forty nine pm reminder to check dinner' (compound minute words)" do
      it "composes tens and ones into a two-digit minute" do
        result = parser.parse("set a six forty nine pm reminder to check dinner")

        expect(result[:intent]).to eq(:reminder)
        expect(result[:params][:hour]).to eq(18)
        expect(result[:params][:minute]).to eq(49)
        expect(result[:params][:message]).to eq("check dinner")
      end
    end

    context "with 'set a six thirty pm reminder to test reminders' (word-form time)" do
      it "parses hour and minute from space-separated spoken digits" do
        result = parser.parse("set a six thirty pm reminder to test reminders")

        expect(result[:intent]).to eq(:reminder)
        expect(result[:params][:hour]).to eq(18)
        expect(result[:params][:minute]).to eq(30)
        expect(result[:params][:message]).to eq("test reminders")
      end
    end

    context "with spoken minute words that require dictionary entries" do
      it "parses 'six fifty pm' as 6:50 PM" do
        result = parser.parse("set a six fifty pm reminder to wrap up")
        expect(result[:params][:hour]).to eq(18)
        expect(result[:params][:minute]).to eq(50)
      end

      it "parses 'six fifty five pm' as 6:55 PM" do
        result = parser.parse("set a six fifty five pm reminder to leave")
        expect(result[:params][:hour]).to eq(18)
        expect(result[:params][:minute]).to eq(55)
      end

      it "parses 'six sixteen pm' as 6:16 PM" do
        result = parser.parse("set a six sixteen pm reminder to check in")
        expect(result[:params][:hour]).to eq(18)
        expect(result[:params][:minute]).to eq(16)
      end

      it "parses 'six seventeen pm' as 6:17 PM" do
        result = parser.parse("set a six seventeen pm reminder to check in")
        expect(result[:params][:hour]).to eq(18)
        expect(result[:params][:minute]).to eq(17)
      end

      it "parses 'six eighteen pm' as 6:18 PM" do
        result = parser.parse("set a six eighteen pm reminder to check in")
        expect(result[:params][:hour]).to eq(18)
        expect(result[:params][:minute]).to eq(18)
      end

      it "parses 'six nineteen pm' as 6:19 PM" do
        result = parser.parse("set a six nineteen pm reminder to check in")
        expect(result[:params][:hour]).to eq(18)
        expect(result[:params][:minute]).to eq(19)
      end
    end

    context "with single-digit spoken minutes" do
      it "parses 'six oh five pm' as 6:05 PM (Deepgram oh-prefix form)" do
        result = parser.parse("set a six oh five pm reminder to take a pill")
        expect(result[:params][:hour]).to eq(18)
        expect(result[:params][:minute]).to eq(5)
      end

      it "parses 'seven zero one pm' as 7:01 PM (zero-prefix form)" do
        result = parser.parse("set a seven zero one pm reminder to check dinner")
        expect(result[:params][:hour]).to eq(19)
        expect(result[:params][:minute]).to eq(1)
      end

      it "parses 'six five pm' as 6:05 PM (no oh-prefix)" do
        result = parser.parse("set a six five pm reminder to take a pill")
        expect(result[:params][:hour]).to eq(18)
        expect(result[:params][:minute]).to eq(5)
      end

      it "parses 'six one pm' as 6:01 PM" do
        result = parser.parse("set a six one pm reminder to leave")
        expect(result[:params][:hour]).to eq(18)
        expect(result[:params][:minute]).to eq(1)
      end
    end

    context "with spoken times at the boundaries of 12-hour clock handling" do
      it "parses 'twelve oh five am' as 12:05 AM (midnight with minutes)" do
        result = parser.parse("set a twelve oh five am reminder to wake up")
        expect(result[:params][:hour]).to eq(0)
        expect(result[:params][:minute]).to eq(5)
      end

      it "parses 'twelve thirty pm' as 12:30 PM (noon with minutes)" do
        result = parser.parse("set a twelve thirty pm reminder to eat lunch")
        expect(result[:params][:hour]).to eq(12)
        expect(result[:params][:minute]).to eq(30)
      end

      it "parses 'eleven fifty nine pm' as 11:59 PM (last minute of the day)" do
        result = parser.parse("set a eleven fifty nine pm reminder to sleep")
        expect(result[:params][:hour]).to eq(23)
        expect(result[:params][:minute]).to eq(59)
      end

      it "parses 'one oh one am' as 1:01 AM" do
        result = parser.parse("set a one oh one am reminder to wake up")
        expect(result[:params][:hour]).to eq(1)
        expect(result[:params][:minute]).to eq(1)
      end
    end

    context "with spoken timer amounts using compound words" do
      it "parses 'twenty five minutes' as 25" do
        result = parser.parse("set a timer for twenty five minutes")
        expect(result[:intent]).to eq(:timer)
        expect(result[:params][:minutes]).to eq(25)
      end

      it "parses 'forty five minutes' as 45" do
        result = parser.parse("set a timer for forty five minutes")
        expect(result[:intent]).to eq(:timer)
        expect(result[:params][:minutes]).to eq(45)
      end
    end

    context "with trailing whitespace in the reminder message" do
      it "strips the message" do
        result = parser.parse("set 7am reminder to write morning pages  ")

        expect(result[:params][:message]).to eq("write morning pages")
      end
    end
  end
end
