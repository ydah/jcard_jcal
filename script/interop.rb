# frozen_string_literal: true

require "json"
require "open3"
require "date"
require "jcard_jcal"
require "icalendar"
require_relative "prepare_rfc_fixtures"

fixtures = RFCFixtures::DIRECTORY
RFCFixtures.verify_fixtures(fixtures)
inputs = Dir[File.join(fixtures, "*.ics")].to_h do |path|
  text = File.read(path)
  unless text.start_with?("BEGIN:VCALENDAR")
    text = "BEGIN:VEVENT\n#{text}END:VEVENT\n" unless text.start_with?("BEGIN:")
    text = "BEGIN:VCALENDAR\n#{text}END:VCALENDAR\n"
  end
  [File.basename(path), text]
end

ruby_calendar = Icalendar::Calendar.new
ruby_calendar.prodid = "-//jcard_jcal interoperability//EN"
ruby_calendar.event do |event|
  event.uid = "interop@example.test"
  event.dtstamp = DateTime.new(2026, 10, 9, 0, 0, 0, "+0")
  event.dtstart = Icalendar::Values::Date.new("20261009")
  event.dtend = Icalendar::Values::Date.new("20261010")
  event.summary = "Comma, semicolon; newline\nand 日本語"
  event.description = "Backslash: \\ and a folded line " * 5
  event.rrule = "FREQ=WEEKLY;BYDAY=MO,WE;COUNT=4"
end
inputs["icalendar-#{Icalendar::VERSION}"] = ruby_calendar.to_ical

output, stderr, status = Open3.capture3("node", File.join(__dir__, "interop_icaljs.js"), stdin_data: JSON.generate(inputs.values))
abort "ical.js failed: #{stderr}" unless status.success?

reference = JSON.parse(output)
failures = []
known_differences = 0
inputs.each_with_index do |(name, text), index|
  parsed = JCal.from_ical(text)
  expected = reference[index]
  if name == "rfc7529_4.3.2_1.ics" && expected["error"] == 'BYMONTH: invalid value "13" must be < 1'
    known_differences += 1
  else
    if name == "rfc7529_4.3.3_1.ics" && expected.dig("data", 2, 0, 1, 1, 3, "bymonth") == 5
      expected["data"][2][0][1][1][3]["bymonth"] = "5L"
      known_differences += 1
    end
    if parsed.to_a != expected["data"]
      failures << name
      warn "#{name}\nRuby:    #{JSON.generate(parsed.to_a)}\nical.js: #{JSON.generate(expected)}"
    end
  end
  raise "Round-trip failed: #{name}" unless JCal.from_ical(parsed.to_ical).to_a == parsed.to_a
end

roundtrip = Icalendar::Calendar.parse(JCal.from_ical(ruby_calendar.to_ical).to_ical).first
before = Icalendar::Calendar.parse(ruby_calendar.to_ical).first.events.first
after = roundtrip.events.first
%i[uid dtstart dtend summary description].each do |field|
  raise "icalendar changed #{field}" unless before.public_send(field) == after.public_send(field)
end

abort "Interoperability mismatches: #{failures.join(", ")}" unless failures.empty?
puts "Compared #{inputs.size} calendars with ical.js 2.2.1: #{known_differences} documented RFC7529 differences."
puts "icalendar #{Icalendar::VERSION} round-trip passed."
