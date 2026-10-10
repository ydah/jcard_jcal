# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require_relative "../script/prepare_rfc_fixtures"

RSpec.describe "validation and fixture provenance" do
  it "reproduces the generated RFC fixtures and correction manifest from downloaded source excerpts" do
    fixtures = RFCFixtures::DIRECTORY
    manifest = JSON.parse(File.read(File.join(fixtures, "manifest.json")))
    Dir.mktmpdir("jcard-rfc-extract") do |directory|
      manifest.group_by { |entry| entry.fetch("rfc") }.each do |rfc, entries|
        sections = entries.group_by { |entry| entry.fetch("section") }.map do |section, examples|
          excerpts = examples.map do |example|
            original = File.read(File.join(fixtures, "#{example.fetch("file")}.original.txt"))
            original.lines.map { |line| "   #{line}" }.join
          end
          "#{section}. Source excerpt\n\n#{excerpts.join("\n")}\n"
        end
        File.write(File.join(directory, "rfc#{rfc}.txt"), sections.join("\n"))
      end
      output = File.join(directory, "generated")
      expect { RFCExamples.extract(directory, output) }.to output(/Extracted #{manifest.size} examples/).to_stdout
      generated = JSON.parse(File.read(File.join(output, "manifest.json")))
      expect(generated.sort_by { |entry| entry.fetch("file") }).to eq(manifest.sort_by { |entry| entry.fetch("file") })
      manifest.each do |entry|
        filename = entry.fetch("file")
        expect(File.read(File.join(output, filename))).to eq(File.read(File.join(fixtures, filename))), filename
      end
    end
  end

  it "ignores RFC page furniture without splitting a section or swallowing the next section" do
    source = "3.1. First section\r\n   FN:Example\r\nAuthor [Page 1]\r\n\fRFC 1234 Header\r\n   " \
             "NOTE:Continued\r\n3.2. Next section\r\n   FN:Next\r\n"
    expect(RFCExamples.sections(source)).to eq([
                                                 ["3.1", "3.1. First section\n   FN:Example\n   NOTE:Continued\n"],
                                                 ["3.2", "3.2. Next section\n   FN:Next\n"]
                                               ])
  end

  it "reports a truncated JSON example instead of emitting an incomplete fixture" do
    expect { RFCExamples.json_blocks("   [\"fn\", {}, \"text\", \"unterminated\"\n") }.to raise_error(/Unclosed JSON/)
  end

  it "rejects grouped, parameterized, and malformed component boundaries" do
    ["item.BEGIN:VCARD", "BEGIN;X-EXTRA=value:VCARD", "BEGIN:VCARD OTHER"].each do |boundary|
      expect { JCard.from_vcard("#{boundary}\nVERSION:4.0\nFN:Example\nEND:VCARD\n") }
        .to raise_error(JCardJCal::ParseError, /boundary/)
    end
  end

  it "preserves recurrence week starts and boundary hour and month-day lists" do
    text = "BEGIN:VCALENDAR\nRRULE:FREQ=MONTHLY;WKST=SU;BYHOUR=0,23;BYMONTHDAY=-31,31\nEND:VCALENDAR\n"
    expected = { "freq" => "MONTHLY", "wkst" => "SU", "byhour" => [0, 23], "bymonthday" => [-31, 31] }
    calendar = JCal.from_ical(text)
    expect(calendar.property("rrule").values).to eq([expected])
    expect(JCal.from_ical(calendar.to_ical).to_a).to eq(calendar.to_a)
  end

  it "rejects recurrence values just outside the valid hour and month-day ranges" do
    ["BYHOUR=-1", "BYHOUR=24", "BYMONTHDAY=0", "BYMONTHDAY=-32", "WKST=XX"].each do |rule|
      expect { JCal.from_ical("BEGIN:VCALENDAR\nRRULE:FREQ=MONTHLY;#{rule}\nEND:VCALENDAR\n") }
        .to raise_error(JCardJCal::ValueError)
    end
  end
end
