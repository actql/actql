# Performance and placement policy follow-up

The second external review, `01-performance-policy (1).md`, inspected
`f9b9dafe89daf73d8b537ba02bfebf627ac92721`. This document records its
findings without treating the earlier review's observations as current source
failures. The registered performance matrix, comparison obligations, and timing
thresholds remain unchanged.

## PERF-24-1: asynchronous appender ownership

The review correctly identified that `openResidentAppender()` did not register
its pending `createAppender()` operation with the session's flight registry.
The body could return or fail while acquisition was pending, allowing cleanup
to race the creation of a native handle. Falsy rejected values could also be
missed by a truthiness check.

Commit `9c443ed45` registers appender acquisition in the same flight registry
as ordinary commands. The session refuses to commit while acquisition is
pending, waits for actual settlement before rollback and connection close, and
retains any late appender for cleanup. Appender failures now use a separate
presence flag and reason, so caught falsy rejections still abort the session.
Existing cleanup ownership and retry remain in force if closing the handle
fails. The change does not add an ActQL state machine to the Node transport.

Product fault-injection tests delay the actual DuckDB `createAppender()` call
and cover an unawaited body return, body failure, cancellation, caught falsy
rejections, and a failed appender close followed by retry. The normal append,
flush, finish, and commit path remains covered. The targeted resident and
session suites passed 32/32 locally. Final-revision Linux CI remains required.

## PERF-24-G1: registered performance acceptance

This is still open. The earlier `d7fa68cd3` assessment belongs to its own
fixed revision and is not evidence for the current implementation. A full
27-case equivalent-obligations run is in progress on clean `f9b9dafe8`; its
result must be recorded with the exact release artifact, raw pairs, and case
assessments. This is only one of four registered comparators. No diagnostic
pair, indeterminate case, or missing case is counted as a pass.

The manual `Registered performance matrix` workflow runs the same registered
equivalent-obligations script on a fixed Linux revision and uploads case pairs,
calibration records, and the assessment even when a gate fails. It excludes
temporary source databases from the review artifact. The final acceptance run
still needs all four comparator families and durable, replayable raw records.
Performance work must preserve real validation, required identities,
independent holding, cleanup, ordinary placement, and the original confidence
and timing gates.
