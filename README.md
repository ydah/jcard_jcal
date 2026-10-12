<h1 align="center">jcard_jcal</h1>

<p align="center">vCard and iCalendar, in text and JSON.</p>

<p align="center">
  <a href="https://rubygems.org/gems/jcard_jcal"><img src="https://img.shields.io/gem/v/jcard_jcal" alt="Gem version"></a>
  <a href="https://github.com/ydah/jcard_jcal/actions/workflows/main.yml"><img src="https://github.com/ydah/jcard_jcal/actions/workflows/main.yml/badge.svg?branch=main" alt="CI"></a>
  <a href="https://www.ruby-lang.org/"><img src="https://img.shields.io/badge/Ruby-%3E%3D%203.3-CC342D?logo=ruby&amp;logoColor=white" alt="Ruby 3.3 or later"></a>
  <a href="LICENSE.txt"><img src="https://img.shields.io/badge/license-MIT-blue" alt="MIT License"></a>
</p>

<p align="center">
  <a href="https://ydah.github.io/jcard_jcal/">Website</a> &middot;
  <a href="#installation">Installation</a> &middot;
  <a href="#quick-start">Quick start</a> &middot;
  <a href="#supported-formats">Supported formats</a> &middot;
  <a href="#development">Development</a> &middot;
  <a href="#license">License</a>
</p>

Convert vCard 4.0 and iCalendar text to and from their JSON representations,
[jCard (RFC 7095)](https://www.rfc-editor.org/rfc/rfc7095) and
[jCal (RFC 7265)](https://www.rfc-editor.org/rfc/rfc7265).

## Installation

Add the gem to your Gemfile:

```ruby
gem "jcard_jcal"
```

Then run `bundle install`.

Requires Ruby 3.3 or later and `json` 2.19.4–3.x. Supports CRuby, JRuby, and TruffleRuby.

## Quick start

```ruby
require "jcard_jcal" # or require "jcard" / require "jcal"

card = JCard.from_vcard("BEGIN:VCARD\nVERSION:4.0\nFN:Alice\nEND:VCARD\n").first
card.properties("fn").first.values # => ["Alice"]
card.to_json                       # => '["vcard",[["version",{},"text","4.0"],["fn",{},"text","Alice"]]]'
card.to_vcard                      # CRLF line endings, UTF-8 safe folding

calendar = JCal.from_ical(<<~ICAL)
  BEGIN:VCALENDAR
  VERSION:2.0
  PRODID:-//Example//Calendar//EN
  BEGIN:VEVENT
  UID:review@example.test
  DTSTAMP:20261001T090000Z
  DTSTART:20261012T010000Z
  SUMMARY:Weekly review
  END:VEVENT
  END:VCALENDAR
ICAL
calendar.components("vevent").each do |event|
  puts event.property("dtstart")&.values
end
JCal.parse(calendar.to_json).to_ical
```

`JCard.from_vcard` returns an array because a text document can contain several
cards. `JCard.parse` and `JCal.parse` each read one JSON component. Properties retain
their order. `to_a`, `params`, and `values` return copies; unknown properties,
parameters, and explicitly declared extension value types are preserved.

## Supported formats

| Supported | Outside this library's scope |
| --- | --- |
| vCard 4.0 ↔ jCard | vCard 2.1/3.0, xCard |
| Nested iCalendar ↔ jCal | Calendar semantic rules such as mandatory DTSTART |
| RFC 6350/5545 value types, partial dates, structured values | Time zone conversion and recurrence expansion |
| RFC 7529 recurrence syntax, including RSCALE/SKIP and leap months | Non-Gregorian calendar calculations |
| RFC 6868 parameter escaping and 75-octet line folding | CardDAV/CalDAV transport, URL fetching |
| RFC 7986 calendar properties and RFC 9554 contact extensions | Other extension-specific semantics without a custom registry |

Text serialization normalizes capitalization, parameter order, folding, and
VERSION placement. It selects the scalar form for a single structured component
and a single parameter value. Binary iCalendar output includes `ENCODING=BASE64`.
These equivalent forms need not retain identical JSON array shapes or parameters
after a round trip. Recurrence rule object keys are lowercase; value case is
preserved. Numeric spelling is normalized, and jCard integer output follows
RFC 7095's truncation rule for fractional JSON numbers.

## Validation and limits

Parsing is strict by default. Syntax failures raise `JCardJCal::ParseError`;
property violations raise `ValidationError` or its subclass `ValueError`.
Errors expose `line_number` for text input or `pointer` for JSON input.
`JcardJcal` and `JCardJCal` refer to the same module.

```ruby
card = JCard.from_vcard(text, strict: false).first
card.warnings.each { |warning| warn warning.message }
```

Lenient text parsing retains an invalid property value as type `unknown` and
records a warning. Lenient JSON parsing retains invalid values with warnings.
Malformed structures, component boundaries, duplicate JSON keys, and resource
limit violations still raise errors. Generation always validates the model.
Binary values remain encoded; the library does not decode attachments.

Both entry points accept the following limits:

| Option | Default |
| --- | ---: |
| `max_input_size` | 16 MiB |
| `max_line_length` | 1 MiB per unfolded content line |
| `max_properties` | 10,000 across the input |
| `max_depth` | 32 component levels |
| `max_binary_size` | 1 MiB of decoded attachment data |

```ruby
JCal.from_ical(text, max_depth: 8, max_properties: 1000)
```

## Custom properties

Default registries are frozen. Duplicate one to add application-specific defaults
without affecting other callers:

```ruby
registry = JCard::Registry.default.dup
registry.register("x-website", type: "uri")
card = JCard.from_vcard(text, registry: registry).first
card.to_vcard # reuses the same registry
```

Register a multiple-valued property with `multiple: true`, or a semicolon-separated
structured property with `structured: true`. An unregistered property without a
VALUE parameter uses `unknown`, keeping the raw content-line value.
Register structured or multiple-valued extensions before converting them through
text; their separators cannot otherwise be distinguished from literal values.

## Development

```sh
bundle install
bundle exec rake test
COVERAGE=1 bundle exec rake test
bundle exec rbs -I sig validate
```

The first test run requires `curl` and HTTPS access to RFC Editor; downloaded
fixtures are cached under `tmp/rfc/`. Run `bundle exec rake fixtures` before
running RSpec directly. See [conformance maintenance](docs/conformance.md) for
fixture updates and property tables.

## Contributing

Bug reports and pull requests are welcome on [GitHub](https://github.com/ydah/jcard_jcal/issues). See [Development](#development) for the checks to run before submitting a change. Report security vulnerabilities privately as described in [SECURITY.md](SECURITY.md).

## License

Released under the [MIT License](LICENSE.txt).
