# frozen_string_literal: true

require "spec_helper"
require "json"
require_relative "../script/prepare_rfc_fixtures"

RSpec.describe "RFC conversion examples" do
  fixtures = RFCFixtures::DIRECTORY
  abort "Run bundle exec rake fixtures before running RSpec directly" unless File.file?(File.join(fixtures, "manifest.json"))
  examples = JSON.parse(File.read(File.join(fixtures, "manifest.json")))

  def card_document(value)
    value = ["vcard", [value]] unless value[0] == "vcard"
    properties = value[1]
    properties.unshift(["version", {}, "text", "4.0"]) unless properties.any? { |property| property[0] == "version" }
    properties << ["fn", {}, "text", "RFC example"] unless properties.any? { |property| property[0] == "fn" }
    value
  end

  def calendar_document(value)
    value = ["vevent", [value], []] if value[1].is_a?(Hash)
    value << [] if value.size == 2
    value[0] == "vcalendar" ? value : ["vcalendar", [], [value]]
  end

  def wrap_content(text, card:)
    if card
      return text if text.start_with?("BEGIN:VCARD")

      "BEGIN:VCARD\nVERSION:4.0\nFN:RFC example\n#{text}END:VCARD\n"
    elsif text.start_with?("BEGIN:VCALENDAR")
      text
    else
      text = "BEGIN:VEVENT\n#{text}END:VEVENT\n" unless text.start_with?("BEGIN:")
      "BEGIN:VCALENDAR\n#{text}END:VCALENDAR\n"
    end
  end

  examples.each do |example|
    filename = example.fetch("file")
    it "round-trips #{filename}" do
      original = File.read(File.join(fixtures, filename))
      card = [6350, 7095].include?(example["rfc"]) || filename.end_with?(".vcf")
      if example["kind"] == "table"
        table = JSON.parse(original)
        expect(table.fetch("rows")).not_to be_empty
        table.fetch("rows").each do |row|
          text = wrap_content("X-EXAMPLE;VALUE=#{table.fetch("type")}:#{row.fetch("text")}\n", card: true)
          json = JSON.generate(card_document(["x-example", {}, table.fetch("type"), row.fetch("json")]))
          if row.fetch("valid")
            model = JCard.from_vcard(text).first
            expect(model.properties("x-example").first.values).to eq([row.fetch("json")])
            expect(JCard.from_vcard(JCard.parse(json).to_vcard).first.properties("x-example").first.values).to eq([row.fetch("json")])
          else
            expect { JCard.from_vcard(text) }.to raise_error(JCardJCal::Error)
            expect { JCard.parse(json) }.to raise_error(JCardJCal::Error)
          end
        end
      elsif example["kind"] == "json"
        data = JSON.parse(original)
        data = card ? card_document(data) : calendar_document(data)
        model = card ? JCard.parse(JSON.generate(data)) : JCal.parse(JSON.generate(data))
        expect(JSON.parse(model.to_json)).to eq(data)
        converted = card ? JCard.from_vcard(model.to_vcard).first : JCal.from_ical(model.to_ical)
        expect(converted.to_a).to eq(model.to_a)
      else
        text = wrap_content(original, card: card)
        models = card ? JCard.from_vcard(text) : [JCal.from_ical(text)]
        models.each do |model|
          converted = card ? JCard.from_vcard(model.to_vcard).first : JCal.from_ical(model.to_ical)
          expect(converted.to_a).to eq(model.to_a)
        end
      end
    end
  end

  [[7095, "B.1"], [7265, "B.1"], [7265, "B.2"]].each do |rfc, section|
    it "matches the paired text and JSON examples in RFC #{rfc} #{section}" do
      card = rfc == 7095
      extension = card ? "vcf" : "ics"
      text = File.read(File.join(fixtures, "rfc#{rfc}_#{section}.1_1.#{extension}"))
      expected = JSON.parse(File.read(File.join(fixtures, "rfc#{rfc}_#{section}.2_1.json")))
      actual = card ? JCard.from_vcard(text).first : JCal.from_ical(text)
      expect(actual.to_a).to eq(expected)
    end
  end

  it "decodes escaped quotes in iCalendar parameters" do
    text = <<~ICAL
      ATTENDEE;CN="Aki ^'Test^' Mori":mailto:aki@example.test
    ICAL
    calendar = JCal.from_ical(wrap_content(text, card: false))
    expect(calendar.components("vevent").first.property("attendee").params["cn"]).to eq('Aki "Test" Mori')
  end

  it "decodes escaped newlines in vCard parameters" do
    text = <<~'VCARD'
      GEO;X-ADDRESS="Studio^nKyoto":geo:35.123456\,135.654321
    VCARD
    card = JCard.from_vcard(wrap_content(text, card: true)).first
    expect(card.properties("geo").first.params["x-address"]).to eq("Studio\nKyoto")
  end

  it "preserves RFC 7529 leap month strings and numeric months" do
    calendar = JCal.from_ical("BEGIN:VCALENDAR\nRRULE:RSCALE=HEBREW;FREQ=YEARLY;BYMONTH=5L,6;SKIP=FORWARD\nEND:VCALENDAR\n")
    expect(calendar.property("rrule").values.first).to eq(
      "rscale" => "HEBREW", "freq" => "YEARLY", "bymonth" => ["5L", 6], "skip" => "FORWARD"
    )
  end

  it "extracts nested JSON without treating brackets in strings as delimiters" do
    expect(RFCExamples.json_blocks("   [\"x-note\", {}, \"text\", \"a ] and \\\"b\\\"\"]\n")).to eq(
      ['["x-note", {}, "text", "a ] and \\"b\\""]']
    )
  end
end
