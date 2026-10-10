# frozen_string_literal: true

require "spec_helper"
require "jcard_jcal/content_line/text_codec"
require "jcard_jcal/content_line/param_codec"
require "jcard_jcal/content_line/reader"
require "jcard_jcal/content_line/writer"

RSpec.describe "content line codecs" do
  it "decodes escaped text without decoding an escaped backslash twice" do
    expect(JCardJCal::ContentLine::TextCodec.decode('one\,two\;three\nfour\Nfive\\\\n'))
      .to eq("one,two;three\nfour\nfive\\n")
  end

  it "encodes text delimiters, backslashes, and platform line endings" do
    expect(JCardJCal::ContentLine::TextCodec.encode("one,two;three\\four\r\nfive\rsix\n"))
      .to eq('one\,two\;three\\\\four\nfive\nsix\n')
  end

  it "splits only unescaped delimiters and retains escaped characters" do
    expect(JCardJCal::ContentLine::TextCodec.split('one\,two,three\\\\,four,', ","))
      .to eq(['one\,two', "three\\\\", "four", ""])
  end

  it "rejects incomplete or undefined text escapes" do
    ['bad\q', "bad\\"].each do |value|
      expect { JCardJCal::ContentLine::TextCodec.decode(value) }.to raise_error(JCardJCal::ValueError)
    end
  end

  it "decodes RFC 6868 parameter escapes once and preserves unknown escapes" do
    expect(JCardJCal::ContentLine::ParamCodec.decode('"one^ntwo^\'three^^n^x^N"'))
      .to eq("one\ntwo\"three^n^x^N")
  end

  it "encodes parameter values and quotes delimiters" do
    expect(JCardJCal::ContentLine::ParamCodec.encode("a,b;c:d\"e^f\r\ng"))
      .to eq('"a,b;c:d^\'e^^f^ng"')
    expect(JCardJCal::ContentLine::ParamCodec.encode("Plain Name")).to eq("Plain Name")
  end

  it "preserves an empty parameter value" do
    expect(JCardJCal::ContentLine::ParamCodec.decode(JCardJCal::ContentLine::ParamCodec.encode("")))
      .to eq("")
  end

  it "rejects malformed parameter quoting and control characters" do
    ['"unfinished', 'a"b', '"a"b', "a,b", "a\rb", "a\u0000b"].each do |value|
      expect { JCardJCal::ContentLine::ParamCodec.decode(value) }.to raise_error(JCardJCal::ValueError)
    end
    expect { JCardJCal::ContentLine::ParamCodec.encode("a\u0000b") }.to raise_error(JCardJCal::ValueError)
  end

  it "rejects invalid UTF-8 at each codec boundary" do
    [JCardJCal::ContentLine::TextCodec, JCardJCal::ContentLine::ParamCodec].each do |codec|
      %i[encode decode].each do |method|
        expect { codec.public_send(method, "\xFF".b) }.to raise_error(JCardJCal::ValueError)
        expect { codec.public_send(method, nil) }.to raise_error(JCardJCal::ValueError)
      end
    end
  end

  it "reads and writes UTF-8 values supplied as binary strings" do
    [JCardJCal::ContentLine::TextCodec, JCardJCal::ContentLine::ParamCodec].each do |codec|
      expect(codec.encode("日本語".b)).to eq("日本語")
      expect(codec.decode("日本語".b)).to eq("日本語")
    end
  end
end

RSpec.describe "content line reader" do
  def read(text, **options)
    JCardJCal::ContentLine::Reader.new(text, **options).to_a
  end

  it "reads folded CRLF and LF lines while preserving one extra leading space" do
    lines = read("DESCRIPTION:An ex\r\n ample\r\n  sentence.\r\nFN:Some\n\tone\n")
    expect(lines.map(&:value)).to eq(["An example sentence.", "Someone"])
    expect(lines.map(&:line_number)).to eq([1, 4])
  end

  it "accepts folding in the middle of a UTF-8 sequence" do
    source = "FN:\xE6\r\n \x97\xA5\n".b
    expect(read(source).first.value).to eq("日")
  end

  it "extracts a group, lowercase property and parameter names, and parameter lists" do
    line = read('Item1.EMAIL;TYPE=work,internet;X-NOTE="a:b;c,d";CN=A^\'B^\':x@example.org').first
    expect(line.name).to eq("email")
    expect(line.group).to eq("Item1")
    expect(line.params).to eq("type" => %w[work internet], "x-note" => "a:b;c,d", "cn" => 'A"B"')
    expect(line.value).to eq("x@example.org")
  end

  it "allows backslashes before delimiters in parameters without treating them as escapes" do
    line = read('X;P="path\\",second:value').first
    expect(line.params).to eq("p" => ["path\\", "second"])
  end

  it "does not treat quotes or colons in property values as header syntax" do
    expect(read('URL:https://example.org/"item"').first.value).to eq('https://example.org/"item"')
  end

  it "rejects malformed lines with the original physical line number" do
    invalid = ["BROKEN", ":value", "A B:value", ".FN:value", "a.b.FN:value",
               "FN;TYPE:value", 'FN;TYPE="a"b:value', 'FN;TYPE="a:value',
               "FN;TYPE=a;type=b:value", "FN:a\rb", "FN:a\u0000b", "FN:\xFF".b]
    invalid.each do |line|
      expect { read("BEGIN:VCARD\n".b + line.b) }.to raise_error(JCardJCal::ParseError) { |error|
        expect(error.line_number).to eq(2)
      }
    end
  end

  it "rejects a continuation without a preceding line and empty physical lines" do
    [" FN:a\n", "\n", "FN:a\n\n"].each do |source|
      expect { read(source) }.to raise_error(JCardJCal::ParseError)
    end
  end

  it "checks physical and unfolded byte limits" do
    expect(read("FN:123\n", max_line_length: 6).first.value).to eq("123")
    ["FN:1234\n", "FN:12\n 34\n", "FN:ああ\n"].each do |source|
      expect { read(source, max_line_length: 6) }.to raise_error(JCardJCal::ParseError, /length/i)
    end
  end

  it "requires a positive maximum line length and a text string" do
    [0, -1, nil, "10"].each do |limit|
      expect { read("FN:a", max_line_length: limit) }.to raise_error(ArgumentError)
    end
    expect { read(nil) }.to raise_error(ArgumentError)
  end
end

RSpec.describe "content line writer" do
  def write(**attributes)
    JCardJCal::ContentLine::Writer.line(**attributes)
  end

  it "writes a group, parameter lists, escaped parameters, and CRLF" do
    result = write(name: "email", group: "Item1", params: { "type" => %w[work internet], "cn" => 'A"B"' },
                   value: "x@example.org")
    expect(result).to eq("Item1.EMAIL;TYPE=work,internet;CN=A^'B^':x@example.org\r\n")
  end

  it "folds at 75 octets including continuation spaces without splitting UTF-8" do
    value = ("a" * 69) + ("日本語" * 20)
    result = write(name: "fn", params: {}, value: value)
    expect(result.split("\r\n").map(&:bytesize)).to all(be <= 75)
    expect(result.split("\r\n")).to all(satisfy(&:valid_encoding?))
    expect(result.split("\r\n").drop(1)).to all(start_with(" "))
    expect(JCardJCal::ContentLine::Reader.new(result).first.value).to eq(value)
  end

  it "does not fold a line that has exactly 75 bytes" do
    expect(write(name: "fn", params: {}, value: "a" * 72)).to eq("FN:#{"a" * 72}\r\n")
  end

  it "rejects case-insensitive duplicate parameter names" do
    expect { write(name: "fn", params: { "type" => "a", "TYPE" => "b" }, value: "a") }
      .to raise_error(JCardJCal::ValueError, /duplicate/i)
  end

  it "writes valid UTF-8 bytes supplied as a binary string" do
    expect(write(name: "fn", params: {}, value: "日本語".b)).to eq("FN:日本語\r\n")
  end

  it "rejects syntax injection and invalid UTF-8 in property values" do
    [{ name: "fn\nX" }, { group: "a.b" }, { value: "a\r\nEND:VCARD" },
     { value: "a\u0000" }, { value: "\xFF".b }, { params: { "A;B" => "x" } },
     { params: { "a" => [] } }, { params: { "a" => 1 } }, { value: nil }].each do |attributes|
      expect { write(name: "fn", params: {}, value: "a", **attributes) }
        .to raise_error(JCardJCal::ValueError)
    end
  end
end
