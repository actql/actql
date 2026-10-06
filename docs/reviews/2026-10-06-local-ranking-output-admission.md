# Retained ranking: resumable output admission

## Boundary and scope

This follows [typed ranking comparisons](2026-10-06-local-ranking-key-scanning.md)
at parent `ff206b0ecda78b00279c6aea17cfead208fbb8da`.
Ranking previously rechecked output group/candidate values and measured a whole
row synchronously. An output row containing long Text could therefore hide its
scan inside one charged transition, independently of the comparison cursor.

[Ranking](../../src/local_veca/ranking.mbt) now assembles borrowed raw fields,
resolves one group position per transition, and drives the existing
[admitted row cursor](../../src/execution_relation/admitted_output_row_steps.mbt).
Each output transition reads one cell, advances one contract recheck, or advances
one logical-charge step. Text rechecking and measurement scan at most 64 UTF-16
units per poll. Final row commit transfers the existing array once.

The existing bounded Session still checks stop requests before transitions.
The provisional row retains its callback, borrowed values and output-buffer lock
until completed or stopped cleanup. Cleanup before confirmed stop returns
`NotStopped`; failure or cancellation retains the pending row for that cleanup.
Successful row cleanup leaves committed rows under their original output owner.
The common row cursor grants no execution-completion or publication authority.

Eight additional fixed structural slots cover row state and observation.
The temporary row reservation is `width+2 = by+5`: `width+1` borrowed row/scope
slots and one logical Text measurement frame. Ranking output keys are flat
KeyComparable values; nested input validation is not claimed by this reservation.
All width arithmetic remains overflow checked.

No algorithm, score policy, NULL rule, order, CID law, Store format, scheduler,
ledger, Run controller or provider-selection contract changes. The generated
API adds a read-only row-poll observation, cleared by stopped cleanup.
D's cancellation owner and H's Effect/Ledger work remain separate.

## Independent boundaries

The numeric four-record RRF fixture requires **212/211** control work and
**117/116** structural slots. Input/sort/duplicate/fusion work remains
`32+88+12+3+16`. Output now costs `4+2*28+1=61`, rather than 15.
Workspace is `4*9+4 + 4*6+4 + (2+2*2) + (1+36) + 6 = 117`.

For the nullable compound-group fixture, input/sort/duplicate/fusion/output-sort
work remains `4*1038 + 1048+2590 + 1033 + 3600 + 1032`.
Output and finalization cost **626**, giving **14081/14080** control work.
Workspace is `4*11+4 + 4*8+4 + (2+2*2) + (3+36) + 7 = 136`,
with **135** refused. Maximum and weighted sum preserve the independently
authored ordered rows across quanta one, seven and 256.

Each five-field long-Text row uses **46** shared cursor polls: twelve for
id/q/rank/score, twelve for segment read/recheck, one to start charging,
eight scalar name/value charges, one segment-name charge, one measurement start,
one value-node charge, nine Text chunks and one commit. The last Text chunk
also completes measurement; it does not require another completion poll.
The two-row logical allowance remains **12 nodes**, **1064 text bytes** and
**1076 work**: two outer nodes plus ten cells and `2*(513+19)` text bytes.
Exact logical limits succeed across quanta; each one-short fails with the
existing typed `RankingOutput(CaptureLimit)`, without a CompletedOutput.

Core cancellation barriers are polls **16**, **38** and **62**: first-row
contract recheck, first-row logical charge and second-row recheck after one
committed row. Pending fields and scratch cannot disappear before stop;
cleanup then clears them once, while both caller-owned inputs remain available.

A mutation draining the entire shared row cursor inside one charged ranking
transition makes the cancellation fixture fail
`ranking did not yield inside output admission` (0/1, `run-1uLsFL`,
`focused-test-rFIzQT`). The mutation was restored before final verification.
This is a synchronous-output-scan counterexample, not an independently measured
historical public Run stop delay.

## Focused verification and public boundary

Matching implementation candidates passed:

- Ranking caller JS: **14/14**, `run-JwLLw8`, `focused-test-o5EWKk`.
- Ranking workspace and reused shared row cursor JS: **10/10**,
  `run-5p6yn8`, `focused-test-tqHdTW`.
- Committed runtime source `664cab5749c86fa604731af12270d9cd3f29e4f6`:
  ranking callers **14/14**, `run-4TzXgF`, `focused-test-RM5XSQ`;
  ordinary retained Host plus resource gate/index **212/212** (1 + 207 + 4),
  `run-N0SVtb`, `focused-test-V4PPgg`.
  The final cleanup changes only this documentation, not runtime/test inputs.
- The final submitted SHA, exact-SHA public regression and evidence-gate results
  are recorded in the pull request. Candidate evidence is not called CI evidence.

Commands:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_integration/local_carrier_vectors_wbtest.mbt --filter '*ranking*'
node scripts/local-checks.mjs test moon -- --target js \
  src/local_veca/ranking_wbtest.mbt \
  src/execution_relation/admitted_output_row_steps_wbtest.mbt
npm run build:runtime-packages -- local-node
node scripts/local-checks.mjs test node -- \
  adapters/host-node/public-ranking-key-retention.test.mjs \
  scripts/check-local-resource-accounting.test.mjs \
  scripts/pure-operation-inventory.test.mjs
```

Only local-node is rebuilt from the matching sources; runtime bundles remain
ignored. The existing ordinary retained-Host RRF harness reads the explicit
producer/two-consumer ordered Named Results and checks request reuse without
another Compute. Its public cancellation barrier is still in group comparison,
not in output admission; output-internal cancellation is proved by the core
caller fixture above. Snapshot reclamation is not a complete holder census.
The resource checker now requires the output logical-limit, stop/cleanup and
reused common-cursor evidence; removing any of those roles fails the gate.

Not newly verified: Wasm/native, full Core, packed/HTTP, proof/performance
campaigns, wall-clock stop latency, whole-Run exact Ledger limits, new Store
failure campaigns, public output-phase cancellation or D's Model restoration.
Draft CI is preparation only and is not merge verification.

## Remaining input work

Ranking input checked-cell rechecks and authored field-name matching still have
synchronous helpers, including unused nested columns. Those require a separate
raw-read/shared-recheck connection and an audit of nested-name/vector scans.
Output field-name equality also retains its existing schema-name contract;
resolving one group position does not make a long identifier comparison stepped.
Conservative noninterruptible value-size observations are intentionally
unchanged. This closes output recheck/measurement, not all ranking or Local
retention work.
