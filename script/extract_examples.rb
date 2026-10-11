# frozen_string_literal: true

# Run with the directory containing RFC Editor text files and an output directory.
require "json"
require "fileutils"

module RFCExamples
  module_function

  def sections(text)
    lines = text.gsub(/\r\n?/, "\n").gsub(/\^L|\f/, "").lines.grep_v(/\A(?:RFC \d+\s|.*\[Page \d+\]\s*$)/)
    chunks = lines.chunk_while { |_, following| !following.match?(/\A(?:\d+(?:\.\d+)*|[AB]\.\d+(?:\.\d+)*)\.\s/) }
    chunks.filter_map do |chunk|
      section = chunk.first[/\A((?:\d+(?:\.\d+)*|[AB]\.\d+(?:\.\d+)*))\.\s/, 1]
      [section, chunk.join] if section
    end
  end

  def json_blocks(text)
    blocks = []
    offset = 0
    while (start = text.index(/^ {3}\[(?:[ \t]*["\n])/, offset))
      depth = 0
      quoted = false
      escaped = false
      finish = nil
      text[start..].each_char.with_index do |char, index|
        if quoted
          if escaped
            escaped = false
          elsif char == "\\"
            escaped = true
          elsif char == '"'
            quoted = false
          end
        elsif char == '"'
          quoted = true
        elsif char == "["
          depth += 1
        elsif char == "]"
          depth -= 1
          if depth.zero?
            finish = start + index + 1
            break
          end
        end
      end
      raise "Unclosed JSON example" unless finish

      blocks << text[start...finish].gsub(/^ {3}/, "")
      offset = finish
    end
    blocks
  end

  def content_blocks(text)
    blocks = []
    lines = text.lines
    index = 0
    while index < lines.size
      match = /\A( {3,})([A-Z][A-Z0-9.-]*[:;])/.match(lines[index])
      unless match
        index += 1
        next
      end
      indent = match[1].length
      block = []
      depth = 0
      loop do
        line = lines[index]
        break unless line

        if line.strip.empty? && depth.positive?
          index += 1
          next
        end
        break unless line.start_with?(" " * indent)

        content = line[indent..]
        break unless content.match?(/\A(?:[A-Z][A-Z0-9.-]*[:;]|[ \t]|\.\.\.)/)

        depth += 1 if content.start_with?("BEGIN:")
        depth -= 1 if content.start_with?("END:")
        block << content
        index += 1
        break if content.start_with?("END:") && depth.zero?
      end
      blocks << block.join unless block.empty?
      index += 1 if block.empty?
    end
    blocks
  end

  def normalize_json(original, rfc, section)
    corrections = []
    value = original.dup
    if value.include?("/*") || value.match?(%r{^\s*(?:\.\.\.|//)})
      value.gsub!(%r{/\*.*?\*/}m, "")
      value.gsub!(%r{^\s*//[^\n]*}, "")
      value.gsub!(/^\s*\.\.\.\s*,?\s*$/, "")
      value.gsub!(/,\s*([\]}])/, '\1')
      corrections << "Removed illustrative comments/ellipsis and their trailing commas."
    end
    if value.match?(/\["vevent"\s*:/)
      value.gsub!(/\["vevent"\s*:/, '["vevent",')
      corrections << "Replaced the colon after vevent with a comma required by JSON arrays."
    end
    if value.match?(/"\s*\+\s*"/)
      value.gsub!(/"\s*\+\s*"/, "")
      corrections << "Joined illustrative string concatenations into a JSON string."
    end
    parsed = JSON.parse(value)
    if rfc == 7095 && section == "B.1.2"
      parsed[1].find { |property| property[0] == "anniversary" }[3] = "2009-08-08T14:30-05:00"
      corrections << "Preserved the source ANNIVERSARY minute precision instead of inserting :00 seconds."
    end
    if rfc == 7265 && section == "3.6.1"
      parsed[1]["encoding"] = "BASE64"
      corrections << "Restored ENCODING=BASE64, required by RFC5545 section 3.2.7 (reported erratum 4862)."
    end
    if rfc == 7265 && section == "3.4.1.2"
      parsed[1][1][3][2] = "ATTENDEE:mailto:jsmith@example.com"
      corrections << "Matched the calendar user's .com domain to the paired iCalendar source."
    end
    if rfc == 7265 && section == "B.2.2"
      parsed[1].sort_by! { |property| property[0] == "version" ? 0 : 1 }
      corrections << "Matched the VERSION/PRODID property order in the source iCalendar example."
      parsed[2][0][2][1][1].find { |property| property[0] == "rrule" }[3]["byday"] = "-1SU"
      parsed[2][1][1].find { |property| property[0] == "rdate" }[3] = ["2006-01-02T15:00:00", "PT2H"]
      parsed[2][2][1].find { |property| property[0] == "dtstart" }[3] = "2006-01-04T14:00:00"
      parsed[2][2][1].find { |property| property[0] == "summary" }[3] = "Event #2 bis"
      corrections << "Matched STANDARD BYDAY=-1SU, the second event's January 4 DTSTART and summary to the source."
      corrections << "Represented the RDATE period as a two-element array required by section 3.6.9."
    end
    [parsed, corrections]
  end

  def normalize_content(original, rfc, section)
    value = original.dup
    corrections = []
    if value.match?(/^\s*\.\.\./)
      value.gsub!(/^\s*\.\.\.\s*\n/, "")
      corrections << "Removed illustrative ellipsis lines."
    end
    if rfc == 7265 && section == "B.1.1"
      value.sub!("DTSTART:20081006", "DTSTART;VALUE=DATE:20081006")
      corrections << "Added VALUE=DATE to DTSTART to match its date-only value and the paired jCal example."
    end
    if [7095, 6350].include?(rfc) && value.include?("TZ:-0500")
      value.sub!("TZ:-0500", "TZ;VALUE=utc-offset:-0500")
      corrections << "Added VALUE=utc-offset to TZ (RFC6350 reported erratum 6746)."
    end
    if [7095, 6350].include?(rfc) && value.match?(/;TYPE="[^"\n]*,[^"\n]*"/)
      value.gsub!(/;TYPE="([^"\n]*,[^"\n]*)"/, ';TYPE=\1')
      corrections << "Removed quotes enclosing a TYPE list (RFC6350 reported erratum 7061)."
    end
    if rfc == 7095 && section == "3.3.1.3" && value.include?("LABEL=")
      value.gsub!('\\n', "^n")
      corrections << "Encoded LABEL newlines using RFC6868 caret notation."
    end
    if rfc == 5545 && value.include?("ORGANIZER:jsmith@example.com")
      value.sub!("ORGANIZER:jsmith@example.com", "ORGANIZER:mailto:jsmith@example.com")
      corrections << "Added ORGANIZER mailto scheme (verified erratum 1916)."
    end
    if rfc == 5545 && value.include?("TRIGGER:19980403T120000Z")
      value.sub!("TRIGGER:19980403T120000Z", "TRIGGER;VALUE=DATE-TIME:19980403T120000Z")
      corrections << "Added TRIGGER VALUE=DATE-TIME (verified erratum 2039)."
    end
    if rfc == 6868 && section == "3.2"
      value.sub!("geo:40.446816,-80.00566", 'geo:40.446816\\,-80.00566')
      corrections << "Escaped the GEO URI comma (verified erratum 4383)."
    end
    [value, corrections]
  end

  def extract(source, output)
    FileUtils.mkdir_p(output)
    manifest = []
    [7095, 7265, 7529, 6350, 5545, 6868].each do |rfc|
      sections(File.read(File.join(source, "rfc#{rfc}.txt"))).each do |section, body|
        next if rfc == 6350 && !["3.2", "6.1.4", "8"].include?(section)
        next if rfc == 5545 && !(section == "3.1" || section.start_with?("3.6") || section == "4")
        next if rfc == 7529 && !["3", "4.3.1", "4.3.2", "4.3.3", "4.3.4", "9"].include?(section)
        next if rfc == 6868 && !["3.1", "3.2"].include?(section)

        body = body.split(/^Authors?'(?:s)? Address/).first

        table_type = { "3.5.3" => "date", "3.5.4" => "time", "3.5.5" => "date-time", "3.5.7" => "timestamp" }[section]
        if rfc == 7095 && table_type
          rows = body.lines.filter_map do |line|
            columns = line.strip.split("|").map(&:strip)
            next unless columns.size == 4 && columns[2].match?(/\A[-\d]/)

            { "text" => columns[2], "json" => columns[3], "valid" => !columns[2].match?(/\A--\d{2}T/), "original" => line.strip }
          end
          name = "rfc#{rfc}_#{section}_table.json"
          File.write(File.join(output, name), "#{JSON.pretty_generate({ "type" => table_type, "rows" => rows })}\n")
          File.write(File.join(output, "#{name}.original.txt"), "#{rows.map { |row| row["original"] }.join("\n")}\n")
          corrections = []
          if rows.any? { |row| !row["valid"] }
            corrections << "The table's --MM date-time rows omit required day components; " \
                           "asserted invalid per section 3.5.5 normative prose and RFC6350 section 4."
          end
          manifest << { "file" => name, "rfc" => rfc, "section" => section, "kind" => "table", "corrections" => corrections }
        end

        json_blocks(body).each_with_index do |original, index|
          value, corrections = normalize_json(original, rfc, section)
          name = "rfc#{rfc}_#{section}_#{index + 1}"
          File.write(File.join(output, "#{name}.json.original.txt"), "#{original}\n")
          File.write(File.join(output, "#{name}.json"), "#{JSON.pretty_generate(value)}\n")
          manifest << { "file" => "#{name}.json", "rfc" => rfc, "section" => section,
                        "kind" => "json", "corrections" => corrections }
        end
        content_blocks(body).each_with_index do |original, index|
          value, corrections = normalize_content(original, rfc, section)
          name = "rfc#{rfc}_#{section}_#{index + 1}"
          extension = [7095, 6350].include?(rfc) || (rfc == 6868 && section == "3.2") ? "vcf" : "ics"
          File.write(File.join(output, "#{name}.#{extension}.original.txt"), original)
          File.write(File.join(output, "#{name}.#{extension}"), value)
          manifest << { "file" => "#{name}.#{extension}", "rfc" => rfc, "section" => section,
                        "kind" => "content", "corrections" => corrections }
        end
      end
    end
    File.write(File.join(output, "manifest.json"), "#{JSON.pretty_generate(manifest)}\n")
    puts "Extracted #{manifest.size} examples."
  end
end

if $PROGRAM_NAME == __FILE__
  abort "Usage: ruby script/extract_examples.rb SOURCE_DIRECTORY OUTPUT_DIRECTORY" unless ARGV.size == 2
  RFCExamples.extract(*ARGV)
end
