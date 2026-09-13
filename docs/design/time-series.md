# Time-series checking

The [time_series](../spec/language.md#time-series) checker admits the closed
generator body and produces a Relation contract with one non-null timestamp
field, `time`. It requires no current input, requires `as` and rejects step
`from`, using the same generator boundary as `values`.

Literal endpoints pass the existing timestamp value admission, including calendar
validity and exact UTC millisecond spelling. Canonical fixed-width UTC strings
have chronological lexical order, so reversed literal intervals fail immediately;
equal endpoints remain valid empty intervals. Parameter endpoints require a
non-null timestamp declaration; defaults are not binding evidence. Step uses
shared positive millisecond admission, including fixed duration tokens and whole
number/duration Parameters. Source and declaration inspection share finite budgets.

The machine schema fixes source shape and timestamp spelling, not calendar
validity, endpoint comparison or Parameter types. Product checking supplies those
static validations. `known_row_count` exposes an exact conditional count when
both endpoints and step are literal, or zero for equal literal endpoints even
when the step still needs binding. The count uses Gregorian UTC milliseconds
in signed 64-bit integers and quotient/remainder ceiling division; it does not
add a potentially large step to the duration. The full admitted timestamp range
fits below 2^49 milliseconds. Year 0000 and century leap rules are included.
Fixed boundary expectations were independently checked against ECMAScript UTC
Date parsing, not derived from the MoonBit implementation.

An unknown count retains `ResolveRowBound`; defaults are never substituted.
A known count does not discharge binding, positive-step validation, checked
arithmetic or resource obligations. Empty intervals still require valid bound
arguments. Output contract construction and constant-time count derivation
are charged during check, and repeated `output` access shares the same immutable
contract instead of constructing unrelated schema handles.

`relation_evidence.time_series_keys` creates the specified `time` candidate-key
witness from the opaque checked generator. `TimeSeriesResult` and
`key_time_series_producer` retain its source, arguments, known count and pending
requirements. The pipeline supplies that witness through later exact projection
and Calendar-bucket transfers to identity completion. No input declaration is
fabricated, including for an empty series. Ordinary timestamp columns alone do
not authorize this proof. `ValidateKeyProducer` remains pending.

No generator rows are materialized here, and this checker does not establish
source coverage or observed absence. The [conditional row-count pass](row-count-evidence.md)
propagates the known count through supported Relation operations. Logical order,
runtime validation and resolved capacity witnesses are separate guarantees; a
typed output or count is not proof that the complete pipeline's execution
resources are resolved.

## Owned generation requirements

The Program operation index retains an exact count after the selected range and
step have been resolved. Generation, exact-count enforcement and the Relation
output ceiling bind to the same input-free checked generator, policy, original
range resolution and optional step resolution. Indexed readers expose these
owned values; equal endpoints or another producer's equal scalar do not replace
the original binding. Even an empty range requires successful step validation.

Counting reuses the admitted Gregorian UTC arithmetic without creating rows or
calling a host clock API. Traversing the operation's requirement group and
reading its fixed-width endpoints consume the shared work budget. Missing or
foreign resolutions fail without returning partial checks. The output ceiling
limits emitted rows, not input coverage, sorting work, retained copies or heap
usage. Backend physical admission remains independent. The retained exact count
is conditional on successful generation and is not a serialized capacity proof
or an observed source-absence claim.
