# Bounded DuckDB physical receipt completion

## Completion unit

Physical Values and selected DuckDB Compute receivers now poll the common
managed receipt cursor introduced by #866 before sealing retained content.
The Native/resident Host and managed-column strategy adapter yield to the Host
between positive polls of at most 64 traversal steps and observe cancellation.
They do not publish partial receipts, restart Compute, reset logical budgets,
or manufacture transport settlement or retained-output evidence.

This branch depends on #866. Its initial source is
`929c404d100382d4beaec11e0551c36e7e56bda7`, which adopted main
`c6a1a8e7ab3726cccbf1fddc897bde15a5927e5a`. The final merge target is main;
the parent branch is only the review base while that dependency is unmerged.

## Before and after

Previously, `managedOutputFinish` and `managedStrategyOutputFinish` drained
all receipt traversal synchronously at these physical call sites. This is a
source-inspection finding, not a reproduced public Run stop-latency measurement.

The existing physical receiver, selected attempt and Node output owner now
expose bounded finish entries. Once polling starts, late appends and competing
blocking finish calls are refused. Nonpositive quantum is rejected without
consuming the receiver. Only an issued receipt is installed on the output and
selected strategy run. Strategy graph/execution binding, input availability,
demand verification, actual transport settlement and exact retained holding
remain mandatory at their existing boundaries.

The Node helper performs no lifecycle decisions. Errors and cancellation return
to the existing caller's cleanup owner. It rejects zero/invalid/oversized poll
progress rather than retrying or rounding work. Cursor traversal steps are
control progress, not invented physical bytes or new logical measurement work.

## Independent checks

- Two physical rows with Number 1 and nullable Text (`"é"`, NULL), reordered
  physical columns: quantum 1/7/64 each requires exactly 19 receipt steps and
  retains measurement `(6, 10, 4)` and the exact checked owner.
- Cancellation after two receipt steps refuses append, competing finish and
  further polling; the existing scratch owner remains unreleased until bounded
  reclamation completes.
- Existing selected-attempt tests use quantum 1 for the guarded physical
  receiver. Transport, demand-limit and input-liveness failures remain typed;
  successful fixed measurement remains `(6, 3, 3)`.
- The actual Node bridge cancels after one incomplete 64-step poll over 20
  rows. No second poll or retained content is issued. This is a bridge/component
  cancellation test, not public Run terminal-state acceptance.
- Native Parquet and real Store manifest consumers retain independently authored
  order and duplicates across two consumers.
- The installed DuckDB cleanup fixture uses a selected Compute receipt spanning
  multiple Host yields, then the production managed-column strategy adapter for
  a 50-row group. Independent expected rows and the existing cleanup retry,
  retained reservation and no-additional-native-attempt assertions remain.
  It uses normal Program preparation plus checked task fixtures, not a pristine
  packed public Named Result acceptance campaign.

## Focused validation

Commands use the repository's pinned Node/MoonBit environment and bounded,
nonzero-test wrapper. Reviewed interfaces are regenerated with `moon info`;
runtime bundles remain ignored.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 300 -- \
  --target js --jobs 1 \
  src/connectors/duckdb/adapter/managed_output_values_wbtest.mbt \
  src/query_integration/managed_compute_attempt_wbtest.mbt
node scripts/local-checks.mjs build moon --timeout-seconds 300 -- \
  --target js --release --jobs 1 \
  src/connectors/duckdb/host_node src/connectors/duckdb/conformance
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  adapters/connectors/duckdb/node/test/managed-output-finish.test.mjs \
  adapters/connectors/duckdb/node/test/managed-manifest.test.mjs \
  adapters/connectors/duckdb/node/test/managed-driver-reclamation.test.mjs
```

Pre-commit checks at parent HEAD plus the implementation diff:

- JS 7/7: `run-iV0dK3`, `focused-test-gVm29Q`. The subsequent test-only change
  adds explicit scratch reclamation and will be checked at the committed source.
- Affected runtime build, 12 tasks: `run-mTFctw`.
- Node 10/10: `run-vJPde2`, `focused-test-RXQ9KD`.

These attempt IDs resolve below `_build/local-checks/attempts` and
`_build/focused-evidence`. They are local diagnostic evidence, not hosted CI.

## Remaining boundaries

This does not close the full retained Local Compute goal. Managed View
aggregate/selection verification still uses its separate existing finish entry.
Physical chunk admission, Local row-file export completion, reference-compute
receipt callers, and trusted callback duration remain separate residuals.
Collector/allocator latency and Native physical lifetime are not bounded by a
receipt traversal count.

No full Core, Wasm/Native core execution, packed/HTTPS, performance or proof
campaign is run for this unit. The inherited actual-history failure documented
in #866 (`Spurious foundation merge bases` on an unchanged main declaration)
is not independently repaired or bypassed here. Final-head hosted CI remains
unverified while the PR is Draft.
