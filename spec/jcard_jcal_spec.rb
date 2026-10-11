# frozen_string_literal: true

RSpec.describe "jCard and jCal public APIs" do
  let(:card_data) do
    ["vcard", [["version", {}, "text", "4.0"], ["fn", {}, "text", "山田 太郎"]]]
  end

  it "retains the generated gem namespace as an alias" do
    expect(defined?(JCardJCal)).to eq("constant")
    expect(JcardJcal).to equal(JCardJCal)
  end

  it "parses jCard JSON and exposes properties" do
    expect(defined?(JCard)).to eq("constant")
    card = JCard.parse(JSON.generate(card_data))
    expect(card.to_a).to eq(card_data)
    expect(card.properties("FN").first.values).to eq(["山田 太郎"])
    expect(JSON.parse(card.to_json)).to eq(card_data)
  end

  it "converts multiple vCards and preserves groups, structured values and extensions" do
    text = "BEGIN:VCARD\nVERSION:4.0\nFN:Test\nitem1.TEL;TYPE=work,voice:tel:+123\n" \
           "N:Family;Given;Middle,Second;;\nX-RAW:a\\,b;c\nEND:VCARD\n"
    cards = JCard.from_vcard(text * 2)
    expect(cards.size).to eq(2)
    card = cards.first
    expect(card.properties("tel").first.group).to eq("item1")
    expect(card.properties("n").first.values).to eq([["Family", "Given", %w[Middle Second], "", ""]])
    expect(card.properties("x-raw").first.type).to eq("unknown")
    expect(card.to_vcard).not_to include("VALUE=UNKNOWN")
    expect(JCard.from_vcard(card.to_vcard).first.to_a).to eq(card.to_a)
  end

  it "converts calendar component trees, multi-values and special structures" do
    text = "BEGIN:VCALENDAR\nVERSION:2.0\nBEGIN:VEVENT\nDTSTART:20260101T120000Z\n" \
           "EXDATE:20260102T120000Z,20260103T120000Z\nGEO:37.386013;-122.082932\n" \
           "REQUEST-STATUS:2.0;Success\nEND:VEVENT\nEND:VCALENDAR\n"
    cal = JCal.from_ical(text)
    event = cal.components("vevent").first
    expect(event.property("dtstart").values).to eq(["2026-01-01T12:00:00Z"])
    expect(event.property("geo").values).to eq([[37.386013, -122.082932]])
    expect(event.property("request-status").values).to eq([["2.0", "Success"]])
    expect(event.property("exdate").values.size).to eq(2)
    expect(JCal.from_ical(cal.to_ical).to_a).to eq(cal.to_a)
    expect(JCal.parse(cal.to_json).to_a).to eq(cal.to_a)
  end

  it "rejects malformed component boundaries with a line number" do
    expect { JCal.from_ical("BEGIN:VCALENDAR\nEND:VEVENT\n") }
      .to raise_error(JCardJCal::ParseError) { |error| expect(error.line_number).to eq(2) }
  end

  it "rejects malformed JSON properties with a JSON Pointer" do
    bad = ["vcard", [["version", {}, "text", "4.0"], ["fn", {}, "integer", "oops"]]]
    expect { JCard.parse(JSON.generate(bad)) }
      .to raise_error(JCardJCal::ValidationError) { |error| expect(error.pointer).to start_with("/1/1") }
  end

  it "preserves invalid text values as unknown in lenient mode with warnings" do
    card = JCard.from_vcard("BEGIN:VCARD\nVERSION:4.0\nFN:T\nBDAY:invalid\nEND:VCARD\n", strict: false).first
    expect(card.properties("bday").first.to_a).to eq(["bday", {}, "unknown", "invalid"])
    expect(card.warnings.length).to eq(1)
    expect(card.warnings.first.line_number).to eq(4)
  end

  it "enforces depth and property limits on text and JSON input" do
    expect { JCal.from_ical("BEGIN:VCALENDAR\nBEGIN:VEVENT\nEND:VEVENT\nEND:VCALENDAR\n", max_depth: 1) }
      .to raise_error(JCardJCal::ParseError)
    expect { JCard.parse(JSON.generate(card_data), max_properties: 1) }.to raise_error(JCardJCal::ParseError)
  end

  it "rejects vCard 3.0 and requires exactly one 4.0 version" do
    expect { JCard.from_vcard("BEGIN:VCARD\nVERSION:3.0\nFN:Test\nEND:VCARD\n") }
      .to raise_error(JCardJCal::ValidationError)
    expect { JCard.parse('["vcard", [["fn", {}, "text", "Test"]]]') }
      .to raise_error(JCardJCal::ValidationError)
  end

  it "returns defensive copies and validates generation" do
    card = JCard.parse(JSON.generate(card_data))
    card.to_a[1][0][3].replace("bad")
    expect(card.to_a).to eq(card_data)
    expect { JCard::Property.new(["fn\nINJECT", {}, "text", "bad"]).to_a }
      .to raise_error(JCardJCal::ValidationError)
  end
end

RSpec.describe "conversion validation and extension preservation" do
  def vcard(line)
    "BEGIN:VCARD\nVERSION:4.0\nFN:Test\n#{line}\nEND:VCARD\n"
  end

  it "keeps a singleton structured text as a scalar" do
    card = JCard.from_vcard(vcard("GENDER:M")).first
    expect(card.property("gender").values).to eq(["M"])
    expect(JCard.from_vcard(card.to_vcard).first.to_a).to eq(card.to_a)
  end

  it "splits commas only for structured properties that support component lists" do
    card = JCard.from_vcard(vcard("ORG:Acme, Inc.;Research")).first
    expect(card.property("org").values).to eq([["Acme, Inc.", "Research"]])
  end

  it "preserves unknown explicitly declared value types" do
    card = JCard.from_vcard(vcard("X-NEW;VALUE=X-OPAQUE:a,b;c")).first
    expect(card.property("x-new").to_a).to eq(["x-new", {}, "x-opaque", "a,b;c"])
    expect(JCard.from_vcard(card.to_vcard).first.to_a).to eq(card.to_a)
  end

  it "uses a copied registry without changing the default" do
    registry = JCard::Registry.default.dup.register("x-page", type: "uri")
    card = JCard.from_vcard(vcard("X-PAGE:https://example.test/a"), registry: registry).first
    expect(card.property("x-page").type).to eq("uri")
    expect(card.to_vcard).not_to include("X-PAGE;VALUE")
    expect(JCard::Registry.default["x-page"]["type"]).to eq("unknown")
  end

  it "reports invalid JSON values as warnings but refuses to generate them" do
    data = ["vcard", [["version", {}, "text", "4.0"], ["bday", {}, "date-and-or-time", "invalid"]]]
    card = JCard.parse(JSON.generate(data), strict: false)
    expect(card.warnings.size).to eq(1)
    expect(card.to_a).to eq(data)
    expect { card.to_json }.to raise_error(JCardJCal::ValueError)
    expect { card.to_vcard }.to raise_error(JCardJCal::ValueError)
  end

  it "rejects invalid structured component counts and nested non-text arrays" do
    [["geo", {}, "float", 1], ["geo", {}, "float", [1, 2, 3]],
     ["request-status", {}, "text", ["2.0"]]].each do |property|
      expect { JCal.parse(JSON.generate(["vcalendar", [property], []])) }
        .to raise_error(JCardJCal::ValidationError)
    end
    expect { JCard.from_vcard(vcard("N:Too;Short")) }.to raise_error(JCardJCal::ValidationError)
  end

  it "rejects extra values on single-valued known properties" do
    data = ["vcalendar", [["summary", {}, "text", "a", "b"]], []]
    expect { JCal.parse(JSON.generate(data)) }.to raise_error(JCardJCal::ValidationError)
  end

  it "rejects duplicate JSON parameter keys on supported json versions" do
    text = '["vcalendar",[["summary",{"language":"en","language":"ja"},"text","T"]],[]]'
    expect { JCal.parse(text) }.to raise_error(JCardJCal::ParseError)
  end

  it "enforces the size and count limits across multiple components" do
    expect { JCard.from_vcard(vcard("NOTE:Test"), max_input_size: 10) }.to raise_error(JCardJCal::ParseError)
    expect { JCard.from_vcard(vcard("NOTE:Test") * 2, max_properties: 5) }.to raise_error(JCardJCal::ParseError)
    expect { JCard.from_vcard(vcard("NOTE:Test"), max_depth: 0) }.to raise_error(ArgumentError)
  end

  it "rejects grouped iCalendar properties and a conflicting vCard GROUP parameter" do
    expect { JCal.from_ical("BEGIN:VCALENDAR\nitem.SUMMARY:Test\nEND:VCALENDAR\n") }
      .to raise_error(JCardJCal::ValidationError)
    expect { JCard.from_vcard(vcard("item1.TEL;GROUP=item2:tel:+123")) }
      .to raise_error(JCardJCal::ValidationError)
  end

  it "rejects malformed JSON trees and incomplete or multiple calendars" do
    ["null", "{}", "[]", '["vcalendar",[],{}]', '["vcalendar",[],[["VEVENT",[],[]]]]'].each do |json|
      expect { JCal.parse(json) }.to raise_error(JCardJCal::ParseError)
    end
    ["", "BEGIN:VCALENDAR\n", "SUMMARY:orphan\n", "BEGIN:VCARD\nEND:VCARD\n",
     "BEGIN:VCALENDAR\nEND:VCALENDAR\n" * 2].each do |text|
      expect { JCal.from_ical(text) }.to raise_error(JCardJCal::ParseError)
    end
  end
end

RSpec.describe "RFC conversion requirements" do
  it "rejects unsafe structured values even in lenient mode" do
    expect { JCard.parse('["vcard",[null]]', strict: false) }.to raise_error(JCardJCal::ParseError)
    data = ["vcard", [["version", {}, "text", "4.0"], ["n", {}, "text", ["A", nil, "", "", ""]]]]
    expect { JCard.parse(JSON.generate(data)) }.to raise_error(JCardJCal::ValueError)
  end

  it "requires VERSION to be the first jCard property" do
    data = ["vcard", [["fn", {}, "text", "T"], ["version", {}, "text", "4.0"]]]
    expect { JCard.parse(JSON.generate(data)) }.to raise_error(JCardJCal::ValidationError)
  end

  it "decodes base64 encoded non-binary calendar content before value conversion" do
    cal = JCal.from_ical("BEGIN:VCALENDAR\nSUMMARY;ENCODING=BASE64:SGVsbG8=\nEND:VCALENDAR\n")
    expect(cal.property("summary").to_a).to eq(["summary", {}, "text", "Hello"])
    expect { JCal.from_ical("BEGIN:VCALENDAR\nSUMMARY;ENCODING=BASE64:!!!!\nEND:VCALENDAR\n") }
      .to raise_error(JCardJCal::ValueError)
  end

  it "generates the mandatory iCalendar binary encoding parameter" do
    cal = JCal.parse('["vcalendar",[["attach",{},"binary","SGVsbG8="]],[]]')
    expect(cal.to_ical).to include("ENCODING=BASE64")
    expect(JCal.from_ical(cal.to_ical).property("attach").values).to eq(["SGVsbG8="])
  end

  it "reads and writes quoted SORT-AS lists" do
    text = "BEGIN:VCARD\nVERSION:4.0\nFN:T\nN;SORT-AS=\"Smith,Alice\":Smith;Alice;;;\nEND:VCARD\n"
    card = JCard.from_vcard(text).first
    expect(card.property("n").params["sort-as"]).to eq(%w[Smith Alice])
    expect(card.to_vcard).to include('SORT-AS="Smith,Alice"')
  end

  it "rejects reserved raw GROUP and VALUE=UNKNOWN declarations" do
    ["FN;GROUP=item1:T", "X-RAW;VALUE=UNKNOWN:T"].each do |line|
      expect { JCard.from_vcard("BEGIN:VCARD\nVERSION:4.0\n#{line}\nEND:VCARD\n") }
        .to raise_error(JCardJCal::ValidationError)
    end
  end
end

RSpec.describe "untrusted property data" do
  it "rejects multi-valued ENCODING without leaking Ruby implementation errors" do
    expect { JCal.from_ical("BEGIN:VCALENDAR\nSUMMARY;ENCODING=BASE64,8BIT:SGk=\nEND:VCALENDAR\n") }
      .to raise_error(JCardJCal::ValidationError)
  end

  it "validates parameter control characters when reading JSON" do
    data = ["vcalendar", [["summary", { "cn" => "a\0b" }, "text", "T"]], []]
    expect { JCal.parse(JSON.generate(data)) }.to raise_error(JCardJCal::ValueError) do |error|
      expect(error.pointer).to eq("/1/0/1/cn")
    end
  end

  it "preserves structured extension properties in JSON and writes their text structure" do
    data = ["vcard", [["version", {}, "text", "4.0"], ["x-test", {}, "text", %w[a b]]]]
    card = JCard.parse(JSON.generate(data))
    expect(card.to_a).to eq(data)
    expect(card.to_vcard).to include("X-TEST;VALUE=TEXT:a;b")
  end

  it "retains an unknown calendar GROUP parameter without allowing group prefixes" do
    data = ["vcalendar", [["summary", { "group" => "local" }, "text", "T"]], []]
    expect(JCal.from_ical(JCal.parse(JSON.generate(data)).to_ical).to_a).to eq(data)
  end
end

RSpec.describe "validation of values that cannot be serialized" do
  it "rejects a prohibited explicit type for a property without a default type" do
    expect { JCal.from_ical("BEGIN:VCALENDAR\nIMAGE;VALUE=BOOLEAN:TRUE\nEND:VCALENDAR\n") }
      .to raise_error(JCardJCal::ValidationError)
  end

  it "reports non-finite numbers in lenient mode through the library error hierarchy" do
    expect { JCal.parse('["vcalendar",[["x",{},"float",1e999]],[]]', strict: false) }
      .to raise_error(JCardJCal::Error)
  end
end

RSpec.describe "binary resource limits" do
  it "keeps an explicitly enlarged binary limit during text generation" do
    encoded = ["a" * 1_048_577].pack("m0")
    data = ["vcalendar", [["attach", {}, "binary", encoded]], []]
    cal = JCal.parse(JSON.generate(data), max_binary_size: 1_048_577)
    expect(cal.to_ical).to start_with("BEGIN:VCALENDAR\r\nATTACH;")
  end

  it "enforces binary limits even with lenient text and JSON parsing" do
    data = ["vcalendar", [["attach", {}, "binary", "SGk="]], []]
    expect { JCal.parse(JSON.generate(data), strict: false, max_binary_size: 1) }
      .to raise_error(JCardJCal::ValueError)
    text = "BEGIN:VCALENDAR\nATTACH;VALUE=BINARY;ENCODING=BASE64:SGk=\nEND:VCALENDAR\n"
    expect { JCal.from_ical(text, strict: false, max_binary_size: 1) }
      .to raise_error(JCardJCal::ValueError)
  end
end

RSpec.describe "constructed component validation" do
  it "rejects invalid names and mismatched root classes during generation" do
    expect { JCal::Component.new("bad:name", []).to_json }.to raise_error(JCardJCal::ValidationError)
    expect { JCard::Card.new("vevent", []).to_vcard }.to raise_error(JCardJCal::ValidationError)
    expect { JCal::Calendar.new("vevent", []).to_json }.to raise_error(JCardJCal::ValidationError)
  end

  it "rejects non-property objects and nested card components" do
    expect { JCal::Calendar.new("vcalendar", [nil]).to_json }.to raise_error(JCardJCal::ValidationError)
    version = JCard::Property.new(["version", {}, "text", "4.0"])
    child = JCal::Component.new("vevent", [])
    expect { JCard::Card.new("vcard", [version], [child]).to_vcard }.to raise_error(JCardJCal::ValidationError)
  end
end

RSpec.describe "resource checks before lenient validation" do
  it "checks every binary value before reporting an unrelated soft violation" do
    properties = [
      ["attach", { "value" => "binary" }, "binary", "SGVsbG8="],
      ["ATTACH", {}, "binary", "SGVsbG8="],
      ["x-data", {}, "binary", "invalid", "SGVsbG8="]
    ]
    properties.zip([3, 3, 4]).each do |property, value_index|
      json = JSON.generate(["vcalendar", [property], []])
      expect { JCal.parse(json, max_binary_size: 4, strict: false) }.to raise_error(JCardJCal::LimitError) do |error|
        expect(error.pointer).to eq("/1/0/#{value_index}")
      end
    end
  end
end
