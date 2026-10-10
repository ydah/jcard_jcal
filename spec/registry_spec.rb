# frozen_string_literal: true

require "spec_helper"
require "jcard_jcal/registry"

RSpec.describe JCardJCal::Registry do
  it "provides immutable property metadata with case insensitive lookups" do
    expect(JCard::Registry.default).to be_frozen
    expect(JCal::Registry.default).to be_frozen
    expect(JCard::Registry.default["BDAY"]).to include("type" => "date-and-or-time", "types" => %w[date-and-or-time date time date-time text])
    expect(JCard::Registry.default["N"]["structured"]).to be(true)
    expect(JCard::Registry.default["TEL"]["type"]).to eq("text")
    expect(JCal::Registry.default["EXDATE"]).to include("type" => "date-time", "multiple" => true)
    expect { JCard::Registry.default["bday"]["types"] << "uri" }.to raise_error(FrozenError)
    expect { JCard::Registry.default.register("x-test", type: "text") }.to raise_error(FrozenError)
  end

  it "registers custom properties without changing defaults" do
    registry = JCard::Registry.default.dup.register("X-CUSTOM", type: "uri")
    expect(registry["x-custom"]["type"]).to eq("uri")
    expect(JCard::Registry.default["x-custom"]["type"]).to eq("unknown")
    expect { registry.register("invalid:name", type: "text") }.to raise_error(ArgumentError)
  end

  it "includes the RFC 7986 and RFC 9554 extensions and section provenance" do
    expect(JCard::Registry.default["socialprofile"]).to include("types" => %w[uri text], "source" => "RFC9554 3.5")
    expect(JCard::Registry.default["created"]["type"]).to eq("timestamp")
    expect(JCal::Registry.default["image"]).to include("types" => %w[uri binary], "value_required" => true)
    expect(JCal::Registry.default["conference"]["source"]).to eq("RFC7986 5.11")
  end
end
