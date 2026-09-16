# Managed output value admission

Date: 2026-09-16.

This increment implements the value-admission part of the registered managed
retained profile. It does not yet implement its common completion or publication.
The existing CID-bearing output receipt and completion APIs remain unchanged.

`ManagedOutputValues` accepts checked cells against the exact checked output
schema. It preserves cumulative admission limits and per-value canonical byte
measurement, but does not construct or hash a canonical row array. Scratch rows
are cleared after each append. The opaque receipt contains bounded metadata,
not row buffers, storage handles, a dummy logical CID or execution authority.

The DuckDB adapter feeds its existing typed physical chunks into this boundary.
Physical decoding, column correspondence and physical result limits remain in
force. Reordered physical columns are mapped to the checked schema. A malformed
later chunk, row overflow or cancellation cannot issue a partial receipt.

## Shared input/output measurement

Fixed Compute can transfer a fully measured `FixedProducerMeasurement` into
`prepare_fixed_managed_output_values`. This consumes the session once and uses
its actual remaining budget. It does not create a new output allowance. Pending
input admission, an already transferred session, and unavailable inputs are
rejected. Input liveness is checked again before receipt issuance and whenever
the receipt is matched to that session. The receipt carries only an opaque
session identity and immutable usage totals, not upstream live handles.

The independent fixture starts with two input rows:
`{"n":1,"s":"é"}` and `{"n":2,"s":"😀"}`. Their top-level values
consume 12 canonical value bytes. Two output numbers consume another 2 bytes.
A 14-byte shared budget succeeds; 13 bytes fails at output row 1, column 0.
The literal total expectation is `(work=10, bytes=14, nodes=6)`, of which output
accounts for `(4,2,2)`. Cancellation and upstream invalidation return no receipt.

Measurement failure is deferred through content admission, as in the existing
streamed path, so later malformed content is not hidden by premature success.
Row and column locations refer to the logical stream across chunk boundaries.
Reentrant finish and repeated finish are rejected.

## Scope of the evidence

Verification passed on JS, Wasm and native: `execution_relation` 413 tests and
DuckDB `adapter` 22 tests per target. Public interface consistency, documentation
and contract checks, formatting and whitespace checks passed. These are package
tests, not a new-profile live DuckDB end-to-end or large-case performance run.

Tests cover value admission, shared budgets and the typed chunk adapter. They
do not yet drive new-profile output from an actual DuckDB execution into a sealed
physical manifest and common Host completion. Value admission is not evidence of
correct computation, an authorized attempt, retention or read permission.

Remaining integration must bind this receipt to the actual generated material,
scoped issuer and attempt, pin/resource ownership and publication obligations.
It must also connect the finite view-transfer rules and the Local path. No
throughput ratio, new-profile end-to-end success, or 1 GiB / 27-case performance
gate completion is claimed here. The per-value measuring work remains real;
only row-array encoding/hashing is absent from this admission path.
