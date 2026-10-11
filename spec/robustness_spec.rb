# frozen_string_literal: true

require "spec_helper"
require "open3"
require "rbconfig"

RSpec.describe "public API robustness" do
  def random_text(random)
    alphabet = ["a", "Z", "0", " ", "\t", "日", "é", "😀", "\\", ",", ";", ":", '"', "^", "\n"]
    Array.new(random.rand(0..90)) { alphabet.sample(random: random) }.join
  end

  def card_data(random)
    ["vcard", [
      ["version", {}, "text", "4.0"],
      ["fn", { "x-label" => random_text(random) }, "text", random_text(random)],
      ["n", {}, "text", [random_text(random), [random_text(random), random_text(random)], "", "", ""]],
      ["categories", {}, "text", random_text(random), random_text(random)],
      ["tel", { "group" => "item#{random.rand(100)}", "type" => %w[work voice] }, "uri", "tel:+123456789"],
      ["x-number", {}, "integer", random.rand(-2_147_483_648..2_147_483_647)],
      ["x-flag", {}, "boolean", random.rand(2).zero?],
      ["x-opaque", { "x-param" => [random_text(random), random_text(random)] }, "unknown", 'a\\,b;c:d^e"f']
    ]]
  end

  def calendar_data(random)
    day = format("%<year>04d-%<month>02d-%<day>02d", year: random.rand(2000..2030), month: random.rand(1..12), day: random.rand(1..28))
    ["vcalendar", [["version", {}, "text", "2.0"]], [["vevent", [
      ["uid", {}, "text", "#{random.rand(1_000_000)}@example.org"],
      ["summary", { "x-label" => random_text(random) }, "text", random_text(random)],
      ["dtstart", {}, "date-time", "#{day}T12:00:00Z"],
      ["rdate", {}, "date-time", "#{day}T13:00:00Z", "#{day}T14:00:00Z"],
      ["categories", {}, "text", random_text(random), random_text(random)],
      ["geo", {}, "float", [random.rand(-90_000_000..90_000_000) / 1_000_000.0, random.rand(-180_000_000..180_000_000) / 1_000_000.0]],
      ["rrule", {}, "recur", { "freq" => "WEEKLY", "byday" => %w[MO WE], "interval" => random.rand(1..30) }],
      ["freebusy", {}, "period", ["#{day}T12:00:00Z", "PT1H"]],
      ["request-status", {}, "text", ["2.0", random_text(random)]],
      ["x-opaque", {}, "unknown", 'a\\,b;c:d^e"f']
    ], [["valarm", [["action", {}, "text", "DISPLAY"], ["trigger", {}, "duration", "-PT15M"]], []]]]]]
  end

  it "round-trips 100 seeded vCards with escaped Unicode, lists, and extensions" do
    random = Random.new(7095)
    100.times do
      data = card_data(random)
      card = JCard.parse(JSON.generate(data))
      expect(JSON.parse(card.to_json)).to eq(data)
      text = card.to_vcard
      expect(text.split("\r\n").map(&:bytesize)).to all(be <= 75)
      expect(JCard.from_vcard(text).first.to_a).to eq(data)
    end
  end

  it "round-trips 100 seeded calendars with typed values and nested components" do
    random = Random.new(7265)
    100.times do
      data = calendar_data(random)
      calendar = JCal.parse(JSON.generate(data))
      expect(JSON.parse(calendar.to_json)).to eq(data)
      text = calendar.to_ical
      expect(text.split("\r\n").map(&:bytesize)).to all(be <= 75)
      expect(JCal.from_ical(text).to_a).to eq(data)
    end
  end

  it "enforces the byte limit before parsing text and JSON input" do
    text = "BEGIN:VCARD\nVERSION:4.0\nFN:A\nEND:VCARD\n"
    json = JSON.generate(["vcard", [["version", {}, "text", "4.0"], ["fn", {}, "text", "A"]]])
    [[JCard.method(:from_vcard), text], [JCard.method(:parse), json]].each do |parser, input|
      expect { parser.call(input, max_input_size: input.bytesize) }.not_to raise_error
      expect { parser.call(input, max_input_size: input.bytesize - 1) }.to raise_error(JCardJCal::ParseError, /size/)
    end
  end

  it "rejects a folded logical line longer than the configured limit" do
    text = "BEGIN:VCARD\nVERSION:4.0\nFN:#{"a" * 20}\n #{"b" * 20}\nEND:VCARD\n"
    expect { JCard.from_vcard(text, max_line_length: 40) }.to raise_error(JCardJCal::ParseError, /length/)
  end

  it "counts properties across sibling components and separate cards" do
    card = "BEGIN:VCARD\nVERSION:4.0\nFN:A\nEND:VCARD\n"
    expect { JCard.from_vcard(card * 2, max_properties: 3) }.to raise_error(JCardJCal::ParseError, /count/)
    calendar = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nUID:one\nEND:VEVENT\nBEGIN:VEVENT\nUID:two\nEND:VEVENT\nEND:VCALENDAR\n"
    expect { JCal.from_ical(calendar, max_properties: 1) }.to raise_error(JCardJCal::ParseError, /count/)
  end

  it "enforces component depth on both text and JSON" do
    data = ["vcalendar", [], [["vevent", [], [["valarm", [], []]]]]]
    text = "BEGIN:VCALENDAR\nBEGIN:VEVENT\nBEGIN:VALARM\nEND:VALARM\nEND:VEVENT\nEND:VCALENDAR\n"
    [[JCal.method(:from_ical), text], [JCal.method(:parse), JSON.generate(data)]].each do |parser, input|
      expect { parser.call(input, max_depth: 3) }.not_to raise_error
      expect { parser.call(input, max_depth: 2) }.to raise_error(JCardJCal::ParseError, /depth/)
    end
  end

  it "rejects binary values above their decoded-size limit before decoding" do
    text = "BEGIN:VCALENDAR\nATTACH;VALUE=BINARY;ENCODING=BASE64:YWJjZA==\nEND:VCALENDAR\n"
    expect { JCal.from_ical(text, max_binary_size: 4) }.not_to raise_error
    expect { JCal.from_ical(text, max_binary_size: 3) }.to raise_error(JCardJCal::ValueError, /size|limit/)
  end

  it "rejects malformed boundaries, parameters, and control bytes in strict and lenient modes" do
    cards = [
      "BEGIN:VCARD\nVERSION:4.0\nFN:Name\nEND:VEVENT\n",
      "BEGIN:VCARD\nVERSION:4.0\nFN:Name\n",
      "BEGIN:VCARD\nVERSION:4.0\nFN;LANGUAGE=en;language=ja:Name\nEND:VCARD\n",
      "BEGIN:VCARD\nVERSION:4.0\nFN;X-PARAM=\"unterminated:Name\nEND:VCARD\n",
      "BEGIN:VCARD\nVERSION:4.0\nFN:Name\x00\nEND:VCARD\n",
      "BEGIN:VCARD\nVERSION:4.0\nFN:\xFF\nEND:VCARD\n".b
    ]
    [true, false].each do |strict|
      cards.each { |text| expect { JCard.from_vcard(text, strict: strict) }.to raise_error(JCardJCal::ParseError) }
    end
  end

  it "rejects structurally invalid JSON even in lenient mode" do
    [nil, true, {}, [], ["vcard", {}], ["vcard", [nil]], ["vcard", [["fn", {}, "text"]]],
     ["vcard", [["fn", nil, "text", "Name"]]]].each do |value|
      expect { JCard.parse(JSON.generate(value), strict: false) }.to raise_error(JCardJCal::ParseError)
    end
  end

  it "contains failures from seeded arbitrary-byte inputs within documented errors" do
    random = Random.new(6868)
    prefixes = ["", "BEGIN:VCARD\nVERSION:4.0\n", "BEGIN:VCALENDAR\nBEGIN:VEVENT\n"]
    300.times do
      source = prefixes.sample(random: random).b + Array.new(random.rand(0..100)) { random.rand(256) }.pack("C*")
      [JCard.method(:from_vcard), JCal.method(:from_ical), JCard.method(:parse), JCal.method(:parse)].each do |parser|
        parser.call(source, strict: random.rand(2).zero?)
      rescue JCardJCal::Error
        # Malformed input must not leak Ruby runtime errors.
      end
    end
  end

  it "contains failures from seeded malformed property arrays within documented errors" do
    random = Random.new(6350)
    atoms = [nil, false, 0, 1.5, "", "fn", "text", "unknown", "recur", [], {}, "bad\nname",
             ["value", nil], { "freq" => "DAILY", "byday" => [true] }, { "x-param" => [nil] }]
    names = %w[fn n bday x-custom rrule geo freebusy]
    types = %w[text date-and-or-time integer float boolean recur period unknown]
    300.times do |index|
      property = if index.even?
                   Array.new(random.rand(0..7)) { atoms.sample(random: random) }
                 else
                   [names.sample(random: random), {}, types.sample(random: random), atoms.sample(random: random)]
                 end
      [JCard, JCal].each do |format|
        document = format == JCard ? ["vcard", [property]] : ["vcalendar", [property], []]
        begin
          component = format.parse(JSON.generate(document), strict: random.rand(2).zero?)
          component.properties("fn")
          component.to_json
        rescue JCardJCal::Error
          # Rejected JSON structures still use the public error hierarchy.
        end
      end
    end
  end

  it "runs the benchmark's assertions and emits elapsed-time and memory measurements" do
    output, error, status = Open3.capture3(RbConfig.ruby, File.expand_path("../script/benchmark.rb", __dir__))
    expect(status.success?).to be(true), error
    rows = JSON.parse(output)
    expect(rows.size).to eq(6)
    rows.each do |row|
      expect(row.fetch("elapsed_seconds")).to be >= 0
      expect(row.fetch("allocated_objects")).to be_nil.or be >= 0
      expect(row.fetch("rss_bytes")).to be_nil.or be > 0
      expect(row.fetch("result")).to match(/accepted|rejected/)
    end
  end

  it "keeps timing parsers when the operating system denies process inspection" do
    denied = "def IO.popen(*); raise Errno::EPERM; end; load ARGV.fetch(0)"
    output, error, status = Open3.capture3(RbConfig.ruby, "-e", denied, File.expand_path("../script/benchmark.rb", __dir__))
    expect(status.success?).to be(true), error
    JSON.parse(output).each do |row|
      expect(row.fetch("rss_bytes")).to be_nil
      expect(row.fetch("rss_before_bytes")).to be_nil
      expect(row.fetch("allocated_objects")).to be_nil.or be >= 0
    end
  end
  it "keeps timing parsers when the runtime has no allocation counter" do
    unsupported = "def GC.stat(*); {}; end; load ARGV.fetch(0)"
    output, error, status = Open3.capture3(RbConfig.ruby, "-e", unsupported, File.expand_path("../script/benchmark.rb", __dir__))
    expect(status.success?).to be(true), error
    JSON.parse(output).each do |row|
      expect(row.fetch("allocated_objects")).to be_nil
      expect(row.fetch("elapsed_seconds")).to be >= 0
    end
  end
end
