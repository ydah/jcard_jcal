# Conformance maintenance

For supported formats and conversion behavior, see the [README](../README.md).

## RFC examples

`bundle exec rake fixtures` downloads the RFC sources listed in
`script/rfc_sources.json`, verifies their SHA-256 hashes, and extracts examples
with `script/extract_examples.rb`. Sources are cached in `tmp/rfc/sources/` and
rechecked on every run. Fixtures are generated under `tmp/rfc/fixtures/` and
checked against `fixtures_sha256` in the source manifest.

When changing extraction, compare generated fixtures with their adjacent
`.original.txt` snippets and review the corrections in
`tmp/rfc/fixtures/manifest.json` before updating the fingerprint. RFC examples
can contradict normative rules; corrections belong in the extractor and manifest.
Tests wrap incomplete property examples in synthetic components.

Downloaded sources retain their author and copyright notices. Extracted code
components carry IETF Revised BSD terms in `tmp/rfc/fixtures/LICENSE`, with
attribution in the manifest and original sources. Keep these test materials
separate from the MIT implementation and out of Git, gem packages, and CI artifacts.

## Property tables

`data/vcard_properties.yml` and `data/ical_properties.yml` define default types
and value shapes and cite their RFC sections. To add or change a definition,
consult the IANA [vCard](https://www.iana.org/assignments/vcard-elements/properties.csv)
or [iCalendar](https://www.iana.org/assignments/icalendar/properties.csv) registry,
read the defining RFC and its errata, and add conversion tests. IANA lists names
and references, so use the RFC for type and structure rules. Unregistered
properties without an explicit VALUE type use `unknown`.

## Implementation and dependency policy

This library is MIT licensed. Additional runtime and development dependencies must offer MIT terms, including transitive dependencies. Ruby, its standard libraries and their system dependencies are the explicit exception. CI checks the resolved bundle with `script/check_licenses.rb`; actual licenses and bundled material still require review when dependencies change.

Previous development comparisons used ical.js (MPL-2.0) and the Ruby icalendar gem (no MIT option). Their installation and runners have been removed. Current tests use the normative RFC examples, locally authored expected values and malformed-input regressions. No external implementation is installed or run by the suite. This does not assert that earlier developers never read other implementations or that the development was clean-room.

The content-line parser, typed property conversion and serializers implement the rules of RFC 6350, RFC 5545, RFC 7095 and RFC 7265, with the supported extensions described in the README. The tables contain identifiers, types and cardinalities; external source code and RFC code components must not be copied into the shipped implementation. The historical provenance review has not identified a copied third-party implementation, but it is not a legal certification of every line's origin.
