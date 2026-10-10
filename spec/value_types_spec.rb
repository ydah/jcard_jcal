# frozen_string_literal: true

require "spec_helper"
require "jcard_jcal/value_types"

RSpec.describe JCardJCal::ValueTypes do
  def convert(text, type, format = :vcard)
    described_class.from_text(text, type, format: format)
  end

  {
    "date" => {
      "20000229" => "2000-02-29", "1985-04" => "1985-04", "1985" => "1985",
      "--0412" => "--04-12", "--04" => "--04", "---12" => "---12"
    },
    "time" => {
      "232050" => "23:20:50", "2320" => "23:20", "23" => "23",
      "-2050" => "-20:50", "-20" => "-20", "--50" => "--50",
      "123000Z" => "12:30:00Z", "123000-0800" => "12:30:00-08:00", "1230+04" => "12:30+04"
    },
    "date-time" => {
      "20130214T123000" => "2013-02-14T12:30:00", "--0412T2320" => "--04-12T23:20",
      "---15T094500+0100" => "---15T09:45:00+01:00"
    },
    "date-and-or-time" => { "T1230" => "T12:30", "1985" => "1985", "---22T1400" => "---22T14:00" },
    "timestamp" => { "20130214T123000-0500" => "2013-02-14T12:30:00-05:00" },
    "utc-offset" => { "-0500" => "-05:00", "+04" => "+04" },
    "boolean" => { "TRUE" => true, "FALSE" => false },
    "integer" => { "42" => 42, "-42" => -42 },
    "float" => { "1.3" => 1.3, "-0.01" => -0.01 },
    "language-tag" => { "de" => "de", "zh-Hant-TW" => "zh-Hant-TW", "x-custom" => "x-custom" },
    "uri" => { "ldap://directory.example.test/cn=test%20person" => "ldap://directory.example.test/cn=test%20person" },
    "unknown" => { 'opaque\\,value' => 'opaque\\,value' },
    "text" => { 'comma\\,semi\\;slash\\\\newline\\n' => "comma,semi;slash\\newline\n" }
  }.each do |type, samples|
    samples.each do |text, json|
      it "round trips #{type} #{text.inspect}" do
        expect(convert(text, type)).to eq(json)
        expect(described_class.from_json(json, type, format: :vcard)).to eq(json)
        expect(described_class.to_json(json, type, format: :vcard)).to eq(json)
        expect(described_class.to_text(json, type, format: :vcard)).to eq(text)
      end
    end
  end

  it "uses full dates, times and second precision offsets for iCalendar" do
    expect(convert("19970101T180000Z", "date-time", :ical)).to eq("1997-01-01T18:00:00Z")
    expect(convert("+053015", "utc-offset", :ical)).to eq("+05:30:15")
    expect { convert("--0412", "date", :ical) }.to raise_error(JCardJCal::ValueError)
    expect { convert("1800", "time", :ical) }.to raise_error(JCardJCal::ValueError)
    expect { convert("19970101T180000+0100", "date-time", :ical) }.to raise_error(JCardJCal::ValueError)
  end

  %w[20230229 20001301 20000431 2025-00 --0230 ---32 202501].each do |text|
    it("rejects invalid date #{text}") { expect { convert(text, "date") }.to raise_error(JCardJCal::ValueError) }
  end

  %w[240000 006000 000061 12:30:00 123000+2500].each do |text|
    it("rejects invalid time #{text}") { expect { convert(text, "time") }.to raise_error(JCardJCal::ValueError) }
  end

  it "rejects reduced dates and truncated times in date-time, and reduced timestamps" do
    %w[1985T12 1985-04T12 --04T12 20000101T-30].each do |text|
      expect { convert(text, "date-time") }.to raise_error(JCardJCal::ValueError)
    end
    expect { convert("20000101T12", "timestamp") }.to raise_error(JCardJCal::ValueError)
  end

  it "converts period endpoints and durations" do
    { "19970308T160000Z/P1D" => ["1997-03-08T16:00:00Z", "P1D"],
      "19970308T160000Z/19970309T160000Z" => ["1997-03-08T16:00:00Z", "1997-03-09T16:00:00Z"] }.each do |text, json|
      expect(convert(text, "period", :ical)).to eq(json)
      expect(described_class.to_text(json, "period", format: :ical)).to eq(text)
    end
    %w[P1D PT2H30M -PT15M +P2W PT0S].each { |v| expect(convert(v, "duration", :ical)).to eq(v) }
    %w[P PT P1Y P1DT P1W2D].each { |v| expect { convert(v, "duration", :ical) }.to raise_error(JCardJCal::ValueError) }
    expect { convert("19970308T160000Z/-P1D", "period", :ical) }.to raise_error(JCardJCal::ValueError)
    expect { convert("19970308T160000Z/19970307T160000Z", "period", :ical) }.to raise_error(JCardJCal::ValueError)
  end

  it "converts recurrence numbers, arrays, and RFC 7529 leap months" do
    text = "RSCALE=HEBREW;FREQ=YEARLY;BYMONTH=5L;BYMONTHDAY=12;SKIP=FORWARD"
    json = { "rscale" => "HEBREW", "freq" => "YEARLY", "bymonth" => "5L", "bymonthday" => 12, "skip" => "FORWARD" }
    expect(convert(text, "recur", :ical)).to eq(json)
    expect(described_class.to_text(json, "recur", format: :ical)).to eq(text)
    expect(convert("FREQ=MONTHLY;INTERVAL=2;BYMONTHDAY=1,15,-1;UNTIL=20131001", "recur", :ical)).to eq(
      "freq" => "MONTHLY", "interval" => 2, "bymonthday" => [1, 15, -1], "until" => "2013-10-01"
    )
    expect(convert("FREQ=WEEKLY;BYDAY=MO,WE", "recur", :ical)).to eq("freq" => "WEEKLY", "byday" => %w[MO WE])
    expect(described_class.to_text({ "freq" => "YEARLY", "bymonth" => [1] }, "recur", format: :ical)).to eq("FREQ=YEARLY;BYMONTH=1")
    expect(convert("RSCALE=HEBREW;FREQ=YEARLY;BYYEARDAY=385", "recur", :ical)["byyearday"]).to eq(385)
    expect(described_class.to_text({ "freq" => "YEARLY", "count" => 2.0, "bymonth" => [1.0] }, "recur", format: :ical)).to eq("FREQ=YEARLY;COUNT=2;BYMONTH=1")
  end

  it "rejects malformed and contradictory recurrence parts" do
    %w[FREQ=NEVER COUNT=5 FREQ=DAILY;COUNT=0 FREQ=DAILY;COUNT=1;UNTIL=20000101
       FREQ=DAILY;FREQ=WEEKLY FREQ=DAILY;BYHOUR=24 FREQ=YEARLY;BYMONTH=13
       FREQ=YEARLY;BYDAY=0MO FREQ=YEARLY;SKIP=FORWARD FREQ=WEEKLY;BYMONTHDAY=1
       FREQ=MONTHLY;BYYEARDAY=1 FREQ=DAILY;BYWEEKNO=1 FREQ=YEARLY;BYSETPOS=1
       FREQ=DAILY;BYDAY=1MO FREQ=YEARLY;BYDAY=1MO;BYWEEKNO=1 FREQ=DAILY; ;].each do |v|
      expect { convert(v, "recur", :ical) }.to raise_error(JCardJCal::ValueError), v
    end
  end

  it "keeps binary encoded and enforces the decoded size without decoding" do
    expect(convert("SGVsbG8=", "binary", :ical)).to eq("SGVsbG8=")
    expect { described_class.from_json("SGVsbG8=", "binary", max_binary_size: 4) }.to raise_error(JCardJCal::ValueError)
    %w[a A=== Zg= Z!== Zh== Zm9=].each { |v| expect { convert(v, "binary", :ical) }.to raise_error(JCardJCal::ValueError) }
  end

  it "preserves unrecognized explicitly named types as opaque strings" do
    expect(convert('one\\,two;three', "x-custom")).to eq('one\\,two;three')
    expect(described_class.to_text('one\\,two;three', "x-custom")).to eq('one\\,two;three')
    expect { described_class.from_json(123, "x-custom") }.to raise_error(JCardJCal::ValueError)
  end

  it "escapes URI commas in vCard while keeping iCalendar URIs unchanged" do
    uri = "geo:35.123456,135.654321"
    vcard = 'geo:35.123456\\,135.654321'
    expect(convert(vcard, "uri", :vcard)).to eq(uri)
    expect(described_class.to_text(uri, "uri", format: :vcard)).to eq(vcard)
    expect(convert(uri, "uri", :ical)).to eq(uri)
    expect(described_class.to_text(uri, "uri", format: :ical)).to eq(uri)
    expect { convert('https://example.com/a\\;b', "uri", :vcard) }.to raise_error(JCardJCal::ValueError)
  end

  it "rejects wrong JSON primitives, nonfinite numbers, malformed URIs, and invalid language tags" do
    [["42", "integer"], [42, "text"], [1, "boolean"], [Float::INFINITY, "float"],
     ["relative/path", "uri"], ["https://example.com/%zz", "uri"], ["en_XX", "language-tag"]].each do |value, type|
      expect { described_class.from_json(value, type) }.to raise_error(JCardJCal::ValueError)
    end
    expect { described_class.from_json(2**31, "integer", format: :ical) }.to raise_error(JCardJCal::ValueError)
    expect { described_class.from_json(1.5, "integer", format: :ical) }.to raise_error(JCardJCal::ValueError)
    expect(described_class.to_text(1.5, "integer", format: :vcard)).to eq("1")
    expect(described_class.to_text(2e20, "float")).to eq("200000000000000000000")
    expect(described_class.to_text(1.2e-8, "float")).to eq("0.000000012")
    expect { described_class.from_json("sl-rozaj-rozaj", "language-tag") }.to raise_error(JCardJCal::ValueError)
    expect { described_class.from_json("en-a-aaa-a-bbb", "language-tag") }.to raise_error(JCardJCal::ValueError)
    expect { described_class.from_json("\xFF".b, "unknown") }.to raise_error(JCardJCal::ValueError)
  end
end
