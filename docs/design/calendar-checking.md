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

## Semantic artifact boundary

`calendar_profile.admit` accepts raw bytes and independently selected byte
CID/release pins. It checks the original hash before parsing, admits the closed
table format defined in the Calendar profile, and hashes canonical re-emission
without materializing a second serialized String. Equality to the original CID
rejects parser normalization repairs, alternate numeric spelling, key order and
whitespace. Duplicate keys fail before a map can erase them. This comparison
uses the same collision-resistance assumption as CIDs.

This format is a new representation decision, not a format supplied by the fixed
reference implementations. The opaque profile binds exact zone lookup to one
selected CID and external release. Current fixtures are synthetic: a trusted real
release fixture, independent historical transition vectors, operation checking
and count/evidence propagation remain. The API does not certify an arbitrary
caller-selected hash as authentic IANA data.

The `calendar_transition` package supplies the validated offset-table primitive
for that boundary. A table has a closed-open UTC millisecond coverage interval,
an initial offset in seconds, and strictly increasing interior transitions.
The new offset applies at the transition instant. Offset-only tables omit
abbreviation and DST-label changes that do not change the offset; redundant
offset transitions are rejected. Initial state represents the coverage start,
so a transition at that start is not a second representation of the same state.
These are normalized-table representation choices, not additional restrictions
on the source TZDB or authored Calendar operations.

Admission checks its transition-count ceiling before traversal or copying and
owns a detached array; indexed access does not expose the array. Lookup is
logarithmic and returns no offset outside coverage, rather than silently
extrapolating. Coverage endpoints are safe JSON integers. Signed offset seconds
use the TZif domain (signed 32-bit except its minimum), not an assumed 24-hour
bound. RFC 9636's narrower recommended range is not a mandatory input limit.
See [RFC 9636, section 3.2](https://www.rfc-editor.org/rfc/rfc9636.html#section-3.2).

The table API neither accepts a profile identity nor certifies IANA provenance.
Its synthetic transition tests establish interval mechanics, validation,
ownership and lookup, not historical TZDB correctness or Calendar conformance.
An admitted table is therefore not sufficient to construct a checked Calendar
operation. The selected artifact boundary must bind tables to the trusted
version, byte CID, conversion law and exact zone names before operation checking.

A nonempty timezone string does not establish IANA membership. The options API
deliberately has no `CheckedCalendar` result and cannot discharge profile or zone
validation. The profile boundary resolves the pinned version, canonical table
bytes and conversion-law identity and validates the local artifact. Name lookup
returns no table for names absent from that artifact. It does not use OS/ICU timezone
data or quietly treat unknown zones as UTC. Missing semantic artifacts prevent
a runnable Plan, including an unpinned UTC shortcut.

The fixed reference revisions do not contain these Calendar operations or a TZDB
artifact to reuse. Operation checking, selection of a real pinned release, conservative
count/evidence propagation and independent transition vectors remain in the full
pure-operation goal. Adding source options does not close those requirements.
Actual calendar evaluation and acquisition of provider data are outside that goal.
