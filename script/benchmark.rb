# frozen_string_literal: true

require_relative "../lib/jcard_jcal"

# RSS includes the Ruby process and retained heap, not just the parsed document.
def resident_bytes
  Integer(IO.popen(["ps", "-o", "rss=", "-p", Process.pid.to_s], &:read).strip) * 1024
rescue SystemCallError, ArgumentError
  nil
end

long_value = "a" * (1_048_576 - "FN:".bytesize)
properties = "VERSION:2.0\n#{"X-BENCH:x\n" * 9_999}"
cases = [
  ["line_at_limit", JCard.method(:from_vcard), "BEGIN:VCARD\nVERSION:4.0\nFN:#{long_value}\nEND:VCARD\n", "accepted"],
  ["line_over_limit", JCard.method(:from_vcard), "BEGIN:VCARD\nVERSION:4.0\nFN:#{long_value}a\nEND:VCARD\n", "rejected"],
  ["properties_at_limit", JCal.method(:from_ical), "BEGIN:VCALENDAR\n#{properties}END:VCALENDAR\n", "accepted"],
  ["properties_over_limit", JCal.method(:from_ical), "BEGIN:VCALENDAR\n#{properties}X-BENCH:x\nEND:VCALENDAR\n", "rejected"],
  ["depth_at_limit", JCal.method(:from_ical), "BEGIN:VCALENDAR\n#{"BEGIN:X-BENCH\n" * 31}#{"END:X-BENCH\n" * 31}END:VCALENDAR\n", "accepted"],
  ["depth_over_limit", JCal.method(:from_ical), "BEGIN:VCALENDAR\n#{"BEGIN:X-BENCH\n" * 32}#{"END:X-BENCH\n" * 32}END:VCALENDAR\n", "rejected"]
]

results = cases.map do |name, parser, source, expected|
  GC.start
  before_memory = resident_bytes
  before_objects = GC.stat[:total_allocated_objects]
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  result = "accepted"
  begin
    parser.call(source)
  rescue JCardJCal::ParseError
    result = "rejected"
  end
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  allocated_objects = GC.stat[:total_allocated_objects] - before_objects if before_objects
  raise "#{name}: expected #{expected}, got #{result}" unless result == expected

  { name: name, source_bytes: source.bytesize, result: result, elapsed_seconds: elapsed.round(6),
    allocated_objects: allocated_objects, rss_before_bytes: before_memory, rss_bytes: resident_bytes }
end

puts JSON.pretty_generate(results)
