# Row-preserving analytic type checking

`relation_typing.check(Analytic, ...)` checks
[analytic](../spec/language.md#analytic) partitions, authored OrderKeys, closed
calls and ROWS frames against the input schema snapshot. Ranking, navigation,
frame-value calls and all sixteen common aggregate signatures are supported.
It does not execute frames, resolve Host limits or construct order proofs.

The checked object retains repeated partition keys, authored peer order and
logical frame boundaries. Every fresh output name is checked against the input,
not earlier sibling calls. Existing field contracts, including join provenance,
are unchanged. The caller retains source input-row order and multiplicity;
analytic order does not become publication order.

`AnalyticPeerOrder` requires the authored peer relation; `AnalyticPositionOrder`
requires completion without splitting those peers. Ranking alone needs the
former, while row_number, navigation and ROWS-frame consumers also need the
latter. `AnalyticFrameDemand` and `AnalyticEnvelope` retain per-call evaluation,
membership, failure-order and capacity obligations. Group aggregate filters
and arguments remain independent retained bindings, with common numeric
observation and statistical-law obligations. No argument is evaluated here.

Call-local pending-validation indices map to their original checked calls through
an owned index. `analytic_call_for_validation` reads that association without
rescanning function arrays or matching equivalent expression text. Frame- and
operation-wide obligations have no call owner. Index construction shares the
type checker's work budget. Indexed partition readers retain repeated references
without copying arrays. These readers neither discharge obligations nor select
resource limits or numeric reduction observations.

Literal frame offsets are compared as exact safe integers. Known class
inversions fail immediately even when an offset is symbolic. Bound numeric
validation is retained separately from unresolved `BoundFrameOrder` checks.
An identical symbolic start/end distance needs no additional comparison, but
still needs its positive-distance validation. Frames are required for aggregate
and first_value/last_value calls, and forbidden for ranking/navigation alone.

Existing selected values may be structured, opaque JSON or references;
navigation retains their domain/bounds with nullable output. This does not
relax the recursive construction rules for array_agg. First_value/last_value
respect NULL, whereas group first/last exclude it. Bare NULL in an overloaded
navigation/value argument is not resolved from a downstream output type.

The fixed reference snapshot has no equivalent authored analytic checker.
This implementation follows the normative frame and demand rules rather than
manufacturing a macro from unrelated grouping or sorting adapters. AoA lowering,
captured values, execution and conformance remain separate work.

The Program resolution index binds an analytic envelope to its exact producer
step, primary input and selected capacity policy. Its typed ceilings distinguish
input/output row-array wire bytes, per-partition wire bytes, frame memberships
and output rows. An absent selected scope leaves the envelope unresolved; no
default bound or zero-usage proof is constructed. Each imported visit keeps the
original operation and its owning policy. These checks reject operation output
on excess, but do not resolve call demand, peer/position ordering, aggregate
result contracts or numeric observations. Logical wire size does not replace
Host admission of physical partition storage and caches.

Analytic execution requirements retain authored peer partitioning separately
from completed position order. Call-demand enforcement preserves the shared
partition/source-position/output-name failure order: filter precedes argument,
each demanded source row is evaluated once per call, and frames reuse that
result. Navigation and first/last value demand only referenced rows. Evaluation
enforces each call's result contract, including safe-integer ranking and typed
NULL for out-of-partition navigation or empty first/last frames. Neither
this obligation nor peer partitioning discharges a missing position witness.

Aggregate demand, scalar result-contract checks and statistical laws bind the
exact analytic call using its original validation index, including imported
producer visits. Array/string frame bounds and binary64 frame observations
require separate selection; ordinary group limits or numeric slots cannot be
substituted. These obligations do not evaluate expressions during checking or
prove that future rows satisfy them. Analytic internal order does not replace
input publication order or create new candidate-key evidence.

The formal Program entry accepts analytic operations only through the same
complete requirement closure as other operations. Ranking, navigation, frame
selection and scalar aggregates can close with their selected resource policy
and required position evidence. Missing resource selection, collection bounds
or numeric-frame observation bindings keep construction incomplete; an earlier
successful Stage is not returned as a partial CheckedProgram. Result imports
carry the original analytic producer's checks and contracts, not newly inferred
consumer-local equivalents. This boundary does not claim an executing backend.

Analytic string aggregation selects the minimum of its own positive `max_bytes`
(including an exactly owned Parameter resolution) and any selected
`max_aggregate_string_bytes`. Both payload-specific ceilings are optional. With
neither selected, the call retains its result-contract check and the separately
mandatory analytic output-wire envelope; no raw-payload ceiling is invented.
The ceiling applies to each non-null frame result's raw UTF-8 payload, including
delimiters after filter, NULL exclusion and ordered distinct. It is not an input
row bound, sum across frames, JSON escaping size or whole analytic output-wire
budget. Exceeding it rejects output, never truncates strings. Other analytic
wire/membership and physical limits remain independent.

The string-bound selection record retains the historical `GroupStringLimit`
API name but contains the exact call and resolution-index owner, not a group
partition or input-size proof. Ordinary group and analytic selectors validate
their own operation kind; shared Host/author selection does not transfer evidence
between those kinds. Repeated producer visits and inventory scans remain charged.

Persistent collection scopes use the producer Unit's authored analytic step and
escaped function name under `/analytic/functions/`, never `/group/aggregates/`.
They name a per-frame bound applying to every result, not a future frame
observation. Input-row evidence uses the distinct analytic array-input law:
each frame is a subset of a partition of input occurrences. Overlapping frames
can have a larger total membership count, so that law does not bound total work
or retained arrays. The subject reader exposes ownership without treating law
registration, a subject string or its hash as proof application or execution.

Array selection uses the required Host item ceiling, any exact authored guard,
and every applicable input-row bound from the owning capacity closure. Sparse
claim slots are scanned to their explicit length; retained memberships keep
their original indices and producer dependencies. Selection validates that each
row bound reaches this analytic input before using its value. Each frame is a
subset of that input, but the bound does not constrain the sum across frames.
The selection record shares the historical `GroupArrayLimit` reader surface and
retains an explicit analytic input-law identifier. Ordinary group selectors
reject analytic occurrences. No observation, position witness or persistent
proof conversion is implied by selection; those remain distinct boundaries.

The owned analytic input-proof reader separately rebuilds an applicable row
proof and its dependencies against the producer Unit, then applies the analytic
array-input law to the per-frame subject. The row witness retains its rows unit;
the new witness has array-items units and names that row witness as its input.
Proof encoding is shared with ordinary group arrays, but ownership, call lookup,
subject and law selection remain operation-specific. A conversion budget failure
returns no partial proof. This reader does not by itself assemble the complete
persistent resolved limit or establish runtime frame contents.
