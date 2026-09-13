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
