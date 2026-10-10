# Security

Report security issues privately to t.yudai92@gmail.com. Include the affected
version and a small reproduction. Do not include private contact or calendar
data. Security fixes target the latest released version.

The library does not fetch URLs, evaluate recurrence rules, or decode binary
attachments automatically. Input size, content-line length, component depth,
property count, and binary attachment size are bounded. Keep those limits in
place when processing untrusted input.
