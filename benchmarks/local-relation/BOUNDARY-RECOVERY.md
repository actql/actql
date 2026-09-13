# One-pass ordinary-path recovery

The user accepted the completion boundary and authorized one performance
recovery pass, without changing thresholds, workloads, measurement conditions
or the evaluator architecture. No second optimization pass follows these results.

## Frozen comparisons

Use the existing diagnostic subset: numeric projection, conditional, ordered
and long-expression cases, 1,000 rows, native/JS, E2E/prepared, seven alternating
pairs per cell (224 successful processes per comparison). Keep raw evidence,
compiler/binary/fixture identities and the independent report audit.

1. Direct attribution: historical `f025ce4` versus `536fef9`.
2. Recovery: `536fef9` versus that exact revision plus the one local patch.
3. Residual: pre-frame baseline `bafdc88` versus the same patched revision.

All measured revisions use the historical `7b655eb` main base, avoiding the
new main compiler/contracts as a confounder. The same product patch is committed
on the current rebased branch for whole-repository correctness verification.
The old baseline receives only the existing audited test-view compatibility
shim and byte-identical shared profiling fixtures. No product overlay is used.

The first sandboxed attempt failed before collecting any sample because macOS
RSS timing requires sysctl permission. Its failed report is retained at
`_build/revision-measurements/1789264915491-68104/report.json`; it is not evidence.
The permitted run collected all 224 samples at
`_build/revision-measurements/1789265022619-68997/report.json`.

## Selected local change

The direct comparison did not identify a reproducible five-percent time
regression caused by completion changes. Several JS cells remain uncertain;
separate earlier reports must not be treated as causal attribution.

Source and generated release JS do show a concrete extra operation introduced
by the boundary: `reserve_table` unconditionally calls a stored reservation
closure, even for default row storage whose closure always returns true and
does no accounting. Generated JS retains that indirect call, so it is not
merely unused source abstraction. It occurs per table, not per cell; it does
not by itself explain the earlier multi-percent timing differences.

This single patch represents the absent hook as `None`, avoiding construction
and invocation of the no-op callback. Explicit typed-storage hooks remain
`Some` and execute before the same common row accounting. It does not remove
the physical reservation boundary, expression frames, events, success evidence
or shared driver. The corresponding private optional-argument plumbing and
one existing typed test call site are adjusted. A fixed test compares absent
and explicit no-op accounting and checks that a rejecting hook still prevents
table installation. Existing typed retained-capacity and failure tests remain.

The patch is justified by the confirmed unnecessary call, not a claim that it
causes the measured residual. Only the fixed post-patch comparisons can show
whether its removal has a measurable benefit. An inconclusive or unfavorable
result is reported rather than initiating another optimization or rollback.
