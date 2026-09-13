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
authored output name. `calendar_typing` checks field existence, non-null timestamp
type and output freshness against a Relation Carrier. Other untyped fields are
retained without inventing their types. An open field set cannot establish
absence of a fresh output name and fails explicitly.

## Operation and pipeline checking

Both Calendar operations now require an admitted `calendar_profile.Profile`.
The pipeline APIs accept it as the optional named `calendar_profile` argument;
omission leaves existing operations unaffected but fails Calendar checking,
including UTC. The checker retains the selected profile with each operation.
Profile selection is not an authored source option or a per-row choice.

Series is input-free, requires `as`, rejects step `from`, and produces a complete
Relation of non-null timestamp `start` and `end`. Bucket consumes the selected
Relation, adds a non-null object with those fields, and preserves existing window
roles because no existing field is changed. It does not fabricate new window-role
evidence from its nested output. Both outputs connect to ordinary Relation
consumers, and all source, parameter and output-schema work shares the pipeline
budget. Diagnostics retain the time, timezone or output-name selector location.

The typed cardinality fact is input preservation for bucket and a finite upper
bound for series. The latter counts possible civil starts in 9999 Gregorian
years (3,652,059 days), divided by the unit with conservative edge allowance.
Folds select one UTC instant and gaps/coincident boundaries cannot add civil
starts. Identical literal endpoints yield the stronger bound zero. This is a
conservative bound, not an evaluated row count or a byte-memory ceiling.
Calendar-value and boundary-domain validation and actual resource ceilings remain
explicit obligations; parameter endpoints also retain binding/range validation.
Candidate-key and ranking-annotation transfers are connected below. The
[conditional row-count pass](row-count-evidence.md) retains bucket counts and
the series upper bound through supported Relation operations; shared logical-order
and resolved resource proof propagation is still separate work.

`CheckedCalendar` retains its bound input (absent for series). Bucket evidence
transfer requires that same row-knowledge or complete-schema handle and uses
the checked output contract. It retains every candidate-key witness and alias,
original producer/declaration, and ranking identity/score annotation on unchanged
fields. Fresh bucket fields gain no such annotation. Arrays and annotation maps
are privately shared rather than rescanned or reconstructed; rebinding keys costs
one unit per witness plus the operation, and ranking annotation transfer is
constant work. Pipeline budgets include these costs.

Series establishes the specification's `start` candidate key, including for an
empty range. `CalendarSeriesResult` and `key_calendar_producer` retain the exact
Calendar producer, selected profile and validation/resource obligations. Bucket
and later exact projections preserve that origin; they do not turn it into a
captured-input declaration or infer runtime completion. A series cannot inherit
unrelated input evidence. These transfers implement existing row-preservation
and start-key rules, not new authored syntax. Actual boundary correctness, logical
order and row-count facts remain separate from the candidate-key witness.

## Semantic artifact boundary

The Program requirement index binds Calendar value admission, boundary-domain
validation and output-envelope enforcement to the original checked operation and
the Environment-selected artifact. Selection lookup is indexed by Stage, producer
visit and step, not repeated for each obligation. A bound series range retains its
original occurrence-specific resolution; equal text from another occurrence is
not a substitute. Literal ranges remain in the checked options.

Bucket value admission precedes use of its input. Generated series values and
boundary-domain checks must succeed before operation output, as must enforcement
of the selected `max_relation_output_rows` ceiling. Failure rejects operation
output; a row ceiling is not timezone validation, a memory bound or a license to
truncate. The profile and range bindings do not compute bucket boundaries,
establish an exact series count or attest observed coverage. Backend support for
the selected artifact and these checks remains a separate execution obligation.
The formal `program_check.check` entry accepts an Environment-owned selected
Calendar artifact through its optional `calendar` argument. Registration topology
rejects a selection from another Environment before preparing any Stage pipeline.
The same admitted profile is passed to every Calendar operation; Result imports
retain their original producer rather than rebuilding a calendar-compatible row
type. Selection verification work is included in the shared topology budget.
Operation closure independently checks the same selection and retains it in the
execution requirements. A profile declaration without the artifact is insufficient,
including for an empty UTC series. This closes source-driven Calendar construction,
not backend timezone evaluation or successful resource enforcement.

`calendar_profile.admit` accepts raw bytes and independently selected byte
CID/release pins. It checks the original hash before parsing, admits the closed
table format defined in the Calendar profile, and hashes canonical re-emission
without materializing a second serialized String. Equality to the original CID
rejects parser normalization repairs, alternate numeric spelling, key order and
whitespace. Duplicate keys fail before a map can erase them. This comparison
uses the same collision-resistance assumption as CIDs.

This format is a new representation decision, not a format supplied by the fixed
reference implementations. The opaque profile binds exact zone lookup to one
selected CID and external release. The selected-zone
[2025b fixture](../../vendor/tzdb/2025b/README.md) is reproduced from pinned IANA
data and compiler archives, alongside synthetic rejection fixtures. It exercises
offsets at gaps, folds, a skipped date and future recurrence through year 9999.
The independent boundary corpus described below fixes conversion expectations;
general logical-order and resolved resource proofs remain unfinished. The API
does not certify an arbitrary
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
artifact to reuse. Production profile selection and shared logical-order and
resolved resource evidence remain in the full pure-operation goal. Adding source
options does not close those requirements. Actual calendar evaluation and
acquisition of provider data are outside that goal.

## Independent boundary vectors

The fixed [boundary corpus](../../portability/corpus/calendar-boundaries.json)
binds its external release, conversion-law domain and transition artifact CID.
Its expected UTC intervals are hand-authored from the normative rule and the
selected historical offsets, not obtained from product output. It covers leap
and non-leap centuries, month/quarter/year boundaries, both weekly origins,
23/25-hour DST days, midnight gaps, earliest folds, Apia's repeated 48-hour day
and skipped date, coincident-boundary collapse, historical second offsets,
future recurrence, unclipped series, closed-open endpoints, empty/reversed
ranges, exact-name lookup and out-of-domain boundaries.

`bucket` cases return a two-element `[start, end]` UTC timestamp array; `series`
returns arrays of those full intervals in UTC order. `resolve` tests the civil
conversion primitive: its `local` timestamp has **no timezone suffix**, whereas
expected instants and bucket/series inputs use canonical UTC timestamps. These
primitive cases do not add an authored operation. An `error` expectation names
an oracle category, not a new public MoonBit diagnostic code.

`scripts/check_calendar_boundaries.py` independently inverts pinned offset
intervals, picks the earliest ambiguous instant, advances gaps to their first
valid instant, and walks Gregorian boundaries with duplicate UTC boundaries
collapsed. Python datetime supplies proleptic Gregorian arithmetic only: there
is no zoneinfo, local timezone conversion, system TZDB or product evaluator call.
The checker compares against fixed expectations and has no write/generate mode.
Its regression tests include mutated fixture bytes and a wrong interval to ensure
that either fails the check. `check:calendar`, and therefore `check:docs`, runs
both the corpus and these regressions after reproducing the transition artifact.

These are independent semantic vectors and oracle tests, not MoonBit Calendar
evaluation conformance. A future evaluator must consume the same fixed cases.
They pin one selected release; they do not claim a differential test against a
second TZDB release or production Check Environment selection.
