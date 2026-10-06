# Retained ranking: resumable typed comparisons

## Boundary and scope

This follows [nearest output admission](2026-10-06-local-nearest-output-admission.md).
The parent is `1fdcb79ae80f1a7eacc9ed3c07fb8e01a86fb42e`.
Ranking formerly counted a whole group/candidate/tie comparison as one control
unit, even when that comparison scanned long Text values or many key columns.
This unit changes operator scanning, not value measurement or Run cancellation.

[The existing shared cursor](../../src/value_admission/key_order_bounded.mbt)
now starts group and author comparisons with the existing domain checks.
Groups remain NULL FIRST and allow the existing KeyComparable reference domain;
author ties remain NULL LAST and exclude that reference domain. A nullable
comparison incrementally validates its non-null side before returning its null
order. Decimal comparison stays exact, without a binary64 conversion.

[Ranking's cursor](../../src/local_veca/ranking_comparison.mbt) borrows keys and
records; it does not copy or flatten a composite key. One charged transition
scans at most one scalar code unit/digit. Constant transitions preserve group,
rank/score, tie, candidate and input-ordinal precedence. Validation, stable
record/output merges, duplicate/rank checks, fusion boundaries, consistent ties
and emitted-group boundaries all reuse it. Pending comparisons cannot advance
record/input positions or apply a numeric contribution twice. RRF retains its
existing rule of not checking tie consistency during the fold.

The existing bounded Session still owns cancellation, stop confirmation and
cleanup. Twelve additional fixed structural slots cover borrowed comparison
state and its observation counter; retained input/output values keep their
separate budgets. Cleanup drops pending roots, clears observations and releases
scratch once. Accepted outputs remain owned by their original completion owner.
No scheduler, ledger, provider-selection rule, wire schema or CID law changes.
D's Run cancellation and H's Effect/Ledger boundaries are not edited.

## Independent bounds and counterexample

- The numeric four-record RRF fixture costs **166/165** control units and
  **103/102** structural slots. Its previous 153-unit total omitted individual
  comparisons: record/output sorting adds eight, duplicate checks add two and
  fusion boundaries add three. Output rows and logical value charges are unchanged.
- The nullable compound-group fixture uses four rows, each containing a
  513-code-unit group and a 513-code-unit author tie. Input costs `4*1038`;
  record sorts `1048+2590`; duplicates `1033`; folds `3600`; output sort `1032`;
  emitted rows and finalization `528`. Total **13983/13982** control units.
  Workspace is `4*11+4 + 4*8+4 + (2+2*2) + (3+28)`: **121/120** slots.
- Maximum and weighted sum independently produce two ordered rows with score
  `0.5`. Quanta one, seven and 256 preserve rows and cumulative work. One-short
  control rejects with `RankingWorkLimit`; one-short workspace rejects before
  execution with `RankingWorkspaceLimit`. Expectations are not sampled usage.
- A two-component group plus candidate visits `3*513=1539` units. Equal-score
  output comparison visits two groups and two ties: `4*513=2052`. The next
  component is never scanned in the same charged transition.

Reintroducing a 10000-unit scalar scan inside one ranking transition makes the
component regression fail `Some(-1) != None` (one failed test, `run-I4hxfQ`,
`focused-test-TrqxcA`). This is a targeted synchronous-scan mutation, not a
claim that a historical public Run cancellation was independently reproduced.
The original implementation was restored immediately; final focused tests pass.

Core cancellation occurs at comparison unit 257, inside the first long group.
Cleanup before confirmed stop returns `NotStopped` and retains the roots and
both inputs. The next advance stops without output progress. Cleanup then
clears all scratch/observations, a second cleanup returns false and borrowed
inputs remain live.

## Ordinary retained Host

[The public harness](../../adapters/host-node/public-ranking-key-retention.test.mjs)
submits ordinary Values plus RRF to the installed Host with a real retained
Store. Explicit producer/two-consumer Named Results match independently authored
ordered rows. Same-request reuse adds neither dispatch nor Compute advances.
At quantum 256, the existing awaited observation hook pauses inside the first
513-code-unit group validation scan, before any output commits. Cancel persists
while physical stop is still unconfirmed; input snapshots remain unchanged.
After release, physical stop is confirmed, all three Results remain unavailable,
and temporary snapshots are reclaimed without another Compute advance/dispatch.
Snapshot reclamation is not a complete holder/reservation census.

An initial Values/max fixture was rejected before execution because it supplied
no registered score evidence. It is not cancellation evidence. The final RRF
fixture uses the normal accepted Values profile; no evidence check or budget was
weakened. Maximum/weighted nullable tie scanning is covered by core fixtures,
not claimed as newly verified through that public fixture.

## Focused validation

Changed source is descended from the parent above. Only `local-node` was rebuilt;
bundles stay ignored. API files were generated by the normal scoped `moon info`.

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/local_veca/ranking_wbtest.mbt src/value_admission/key_order_wbtest.mbt
node scripts/local-checks.mjs test moon -- --target js \
  src/query_integration/local_carrier_vectors_wbtest.mbt --filter '*ranking*'
node scripts/local-checks.mjs test node -- \
  adapters/host-node/public-ranking-key-retention.test.mjs
node scripts/local-checks.mjs test node -- \
  scripts/check-local-resource-accounting.test.mjs \
  scripts/pure-operation-inventory.test.mjs
```

- Comparisons: **13/13**, `run-x02HiL`, `focused-test-yfQoPV`.
- Actual ranking callers: **12/12**, `run-vfEATT`, `focused-test-rtShNc`.
- Installed Host: **1/1**, `run-PKHjA0`, `focused-test-TNnWIz`.
- Resource gate/index: **210/210** (206 + 4), `run-acPghg`,
  `focused-test-87vyq2`. Missing roles and an omitted actual suite import fail.
- An invalid compound glob discovered zero tests and was correctly rejected;
  it is not counted as validation. The explicit selections above replaced it.

Not executed: Wasm/native, full Core, packed/HTTP, proof campaigns, performance,
wall-clock stop measurements, new Store-failure campaigns or D's restored Model
cancellation acceptance. The target is main after the parent stack is integrated.

## Concrete residuals

Ranking input checked-cell rechecks and name matching still use existing
synchronous helpers. Output contract rechecks and whole-row append/measurement
also remain synchronous. Conservative noninterruptible value-size observations
are intentionally unchanged. These are separate input/output admission units,
not hidden by this operator-comparison claim. Local retention is not complete.
