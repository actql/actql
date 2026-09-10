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
static validations. Bound-value range, arithmetic overflow, exact row-bound
derivation and resource resolution remain explicit obligations before execution.
No generator rows are materialized here, and this checker does not establish
source coverage or observed absence. Candidate-key and order evidence require
the pipeline's validated proof boundary; a typed output is not that proof.
