# Bounded managed View completion

## Completion boundary

The existing managed View output owner now resumes its trusted verification,
finite column admission, ordered index diagnosis and common receipt issuance.
The DuckDB managed-column strategy adapter uses that same owner through the
bounded output bridge before sealing and retaining content. The blocking common
convenience entry drains the same cursor; it is not a second verifier or a
compatibility fallback.

This branch starts from #869 at
`0bd079674c692de3a9c98f6ce65b3f6d1b1675d7`, with #866 as its ancestor dependency.
The final merge target is main. Keep the parent review base while it is unmerged;
do not merge this unit into the dependency branch.

## Ownership and accounting

- Verification consumes the port once. Reentrant or competing finish attempts
  cannot discard the active selection index or reopen the reserved stream.
- Each poll visits at most its positive traversal quantum. Finite summary
  admission and ordered diagnostics are common code, not an adapter's summary
  assertions. Existing View/verified-output callers share one facts algorithm.
- Validated column scalars are stored immediately in existing private metadata.
  They are never reread from mutable verifier facts after a yield. This avoids
  a second, unaccounted per-column snapshot allocation. A changed pending width
  is rejected with `InconsistentFacts`.
- Successful summary measurement commits to the original guard once. Ordered
  diagnosis charges that original guard row-by-row and cell-by-cell. Quantum
  does not change logical work, bytes, nodes, first failure position or cause.
- The exact input remains live across pending polls and before receipt issuance.
  Cancellation/revocation prevents issuance. A successful receipt owns its
  transferred index independently; cancelling the consumed port cannot clear it.
- Partial facts and receipt copies remain under existing scratch/cleanup owners.
  Physical Store cleanup and task settlement are not inferred from logical
  cancellation, and no Compute retry or alternate completion is introduced.

## Independent fixtures

The wide fixture starts with authored rows `n=1,s="é"` and `n=2,s="😀"`, then
copies `n` into 100 fields using the checked derive kernel. Its 102 columns and
two rows require guard work 206, bytes 212 and nodes 204. Quanta 1/7/64 all require
213 completion traversal steps: verifier 1, facts 102+3, receipt 102+5.

Exact limits succeed; work 205 produces `MeasurementWork`, and bytes 211 or
nodes 203 produces the existing `Measurement(Output,1,101,OutputLimit)` cause.
Cancellation and input revocation are exercised at five intermediate positions,
including just before issuance. Source index custody survives private cleanup.
Cancellation during ordered diagnosis preserves consumed guard work/capacity.

A mutation regression replaces an already validated numeric column fact with
1,000,000 bytes. The initial uncommitted cursor candidate reread that fact and
failed the independent `(2,2)` expectation; the corrected cursor preserves the
validated private scalars. This is a development-candidate counterexample, not
a claimed public Run defect in main. Pending width growth/shrink is also refused.

The existing actual DuckDB/real-Store caller verifies selected/preserved/chained
and computed outputs, NULL/text facts, exact physical holding, independent
expected rows, completion/revocation, consumers and final Store reservations.
Selected View and filter finish calls now use the bounded bridge. A separate
partial-verifier cancellation probe prevents retention and leaves the completed
source alive; that probe is component evidence, not public Run terminal-state
acceptance or a substitute for actual execution proof.

## Focused commands and preparation evidence

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 1 \
  src/execution_relation/managed_view_finish_wbtest.mbt \
  src/execution_relation/managed_view_output_wbtest.mbt \
  src/execution_relation/managed_view_selection_wbtest.mbt \
  src/execution_relation/managed_index_diagnostic_wbtest.mbt \
  src/execution_relation/managed_verified_output_wbtest.mbt
node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  adapters/connectors/duckdb/node/test/managed-compute-host.test.mjs
```

Local preparation evidence at parent HEAD plus the implementation diff:

- Compilation-only failures: `run-v6yLr6`/`focused-test-gzPhmT` and
  `run-I40Qz6`/`focused-test-zc9qM8`. They are not executed success evidence.
- Initial focused issuer/caller selection: 18/18,
  `run-n822JS`/`focused-test-IXZExb`.
- Mutation counterexample: 0/1, `run-V1il4G`/`focused-test-mt0bEI`.
- Corrected selection before two final regressions: 19/19,
  `run-8Gcy7Z`/`focused-test-a4okdO`.
- Actual runtime/Store caller: 1/1 (one top-level matrix, not one case per inner
  variant), `run-Dyf4nw`/`focused-test-LR4VgK`. Its fixture prepares the two
  consumed DuckDB runtime roots. Affected common and Host interfaces were
  canonically regenerated.

Attempt IDs resolve below `_build/local-checks/attempts` and
`_build/focused-evidence`. They establish only the source and command recorded
by each receipt, not hosted CI or a pristine packed distribution.

## Clean implementation verification

The commands above also passed on clean implementation SHA
`14e1c1d0c911bea94f4d05417198a27e217d7ed3`:

- Focused JS: 21/21, `run-1AE5hg` / `focused-test-dRSBpt`.
- Actual DuckDB/Store Node caller: 1/1,
  `run-wEM8zv` / `focused-test-0MF4nL`.
- Both receipts record that exact SHA with `dirty: false`, complete output,
  exit zero and a passing nonzero-test guard. No packed tarballs were produced.
- MoonBit formatting, affected generated public interfaces, Node Host/Workers
  fixture freshness, whitespace and 72-column commit-message checks passed.

The following evidence-record commit changes documentation only. Executed
receipts remain tied to the implementation SHA; they are not relabelled as
execution of the later submitted HEAD. An earlier message-only amendment
preserved the tree and parent of `72ed9b745cecc2ab75bca69576d09c909e81c56c`;
the clean verification above was executed after that amendment.

## Remaining scope

This closes finite View facts/index diagnosis and its receipt/Host connection,
not every View preparation or retained Local path. Selecting/copying occurrence
metadata remains a separate synchronous preparation boundary. Trusted verifier
and availability callbacks, physical chunk admission, Local row-file finish,
other receipt callers, collector latency and Native physical-byte correspondence
are not made bounded by this cursor.

Full Core, Wasm/Native core execution, packed/HTTPS, performance and proof
campaigns are not run for this unit. The unchanged-main actual-history failure
reported in #866 is retained as a known shared issue, not bypassed or repaired
independently. Final-head hosted CI is unverified while the PR is Draft.
