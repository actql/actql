# Calendar admission boundaries

The normative owner is the [Calendar profile](../spec/language.md#calendar).
The current `calendar_options` package admits closed bucket/series source options,
not an executable operation. Its opaque `Options` retain unit, exact timezone
spelling, weekly origin and source fields or range endpoints with bounded usage.

Literal timestamp ranges use calendar value admission and the narrower Calendar
year domain 0001..9999. Parameters require non-null timestamp declarations but
their defaults are not bindings. Equal endpoints are admitted without inventing
rows; reversed literals fail at the end source location. Unit, timezone and week
origin are fixed literal selectors, not data-dependent expressions.

The time field accepts ordinary qualified reference spelling; `into` remains an
authored output name. Field existence, timestamp type and freshness are the
operation checker's responsibility. The options package does not yet connect
either operation to pipeline dispatch or produce a checked output Carrier.

## Remaining semantic artifact boundary

A nonempty timezone string does not establish IANA membership. The options API
deliberately has no `CheckedCalendar` result and cannot discharge profile or zone
validation. The next boundary must resolve the pinned version, canonical table
bytes and conversion-law identity, validate the local artifact, and reject names
not present in that selected artifact. It must not use ambient OS/ICU timezone
data or quietly treat unknown zones as UTC. Missing semantic artifacts prevent
a runnable Plan, including an unpinned UTC shortcut.

The fixed reference revisions do not contain these Calendar operations or a TZDB
artifact to reuse. Operation checking, the validated artifact boundary, conservative
count/evidence propagation and independent transition vectors remain in the full
pure-operation goal. Adding source options does not close those requirements.
Actual calendar evaluation and acquisition of provider data are outside that goal.
