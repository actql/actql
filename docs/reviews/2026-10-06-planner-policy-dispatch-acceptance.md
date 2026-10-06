# Planner policy admission and observation cost

Owner: G. This supplements the integrated #458/#507 planner/benchmark work for
#170. It does not reopen the merged Native batch experiment or claim an
additional speedup. #507 head `2cdcb514beac98805e1f808c156895d4552b2c76` was
merged as `d093bcedf8b64b5d7b3e8fdecc988310c51bff90`; the user independently
reviewed its fixed before/after observations and accepted that limited result.

## Actual policy and dispatch connection

The current DuckDB standard Host imports `physical_host` as `host_driver`.
Its estimate/policy entry points delegate to `prepare_compute_host_policy_choice`,
`prepare_compute_host_policy_request`, `commit_compute_host_policy_response_json`
and `commit_compute_host_policy_choice`. Candidate selection, authenticated
preference admission and dispatch revocation remain with the existing
provider-neutral Host and physical strategy owners. The Native HTTP/mTLS/clock
implementation remains an adapter; this review found no need for a second
policy owner or a production refactor.

The existing `standard Host commits an authenticated external policy before
dispatch` test now checks five invalid responses through that actual adapter:
wrong peer, expired response, foreign Run, foreign authority and wrong position.
For each rejection it requires no installed strategy/history, `NoStrategy` at
the real prepare-dispatch entry, no completed task or published output, and an
unchanged ledger. It then admits the valid response, confirms the actual Local
registration, executes the dispatch and checks the independent one-row value
`Number(3.0)`. One physical attempt is charged. The actual dispatch, public
outputs and fixture issuer are closed; holding and reservations return to zero
and repeated stop leaves the ledger unchanged.

These are authenticated-policy/Owner tests, not HTTP service acceptance. The
separate Native mTLS test is environment-guarded and was not selected; returning
early from that test is not counted as transport verification. The genuine
Local/fresh/resident Compute implementations and preparation/import accounting
are exercised by the earlier fixed-SHA Native benchmark acceptance, not by
relabeling this Local Graph fixture as a resident execution.

## Fixed-SHA verification

The source test was committed at
`0a08670f9f8be2d78785fbaed970f84a81f1b626`. Its clean-HEAD focused JS receipt
`run-pE5MWF` / `focused-test-iBEhNX` passed **1/1**. Existing priority/tie and
revision tests passed **5/5 JS** in `run-3A7oVd` on the preceding working diff;
that result is not retagged as clean-HEAD evidence.

After normally merging main `582bed59b14cb10eb309744765d3c54ef5cb1369`, the
source head `c8ddd6a636b30e527ca0382e8bd1b5a0f1f4c454` passed the same **1/1 JS**
case in `run-n7RFK0` / `focused-test-6nB47q`:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js src/query_integration/physical_adaptive_dispatch_wbtest.mbt \
  --filter '*authenticated external policy before dispatch*'
```

The pinned MoonBit `MOON_HOME`/`PATH` was supplied as required. The first
sandboxed launch failed at process-group inspection before starting tests. The
same command was then executed with the normal permission path, retaining the
guard. No guard was removed, no Actions environment was simulated, and no
performance matrix, packed acceptance or Native rebuild was added.

## Observer-cost diagnostic: all four samples retained

The already executed `node-observation-cost.mjs` diagnostic used a clean
`0a08670f9f8be2d78785fbaed970f84a81f1b626` controller, the existing 100-row
numeric/narrow case and order **off/on/on/off**. It passed **1/1 Node** in
`run-XNKAvo` / `focused-test-4cpZlW`:

```sh
node scripts/local-checks.mjs test node --timeout-seconds 120 -- \
  benchmarks/retained-results/node-observation-cost.mjs
```

The complete emitted record is preserved unchanged in
[the raw record](2026-10-06-node-planner-observation-cost.json), SHA-256
`e8f1a2863cbb5bca5be91c831dd989208e89c89ebf17bec84c9e61e4418c54ab`.
The original receipt/stdout remains in the worktree. The portable release
modules were prepared at `58ec55085f78b22eef890a99778bf05f5749c2f3`
(`run-GkY4LT`); the product sources differ from the diagnostic controller only
in the whitebox test file above. A later full-byte read confirms the same seven
release modules' combined digest
`0d92ea84a7ce4fe4a03c1d87aa5e82b574893e84dc032efd28703a829765fe4a`.
This later read is not a claimed artifact measurement inside the earlier run.
The diagnostic was not repeated or retagged for the newer integrated main.

| Sample | Observer | Execution, ms | Cleanup, ms | Wrapper elapsed, ms |
| --- | --- | ---: | ---: | ---: |
| 1 | off | 1266.475458 | 1.787709 | 1275.477167 |
| 2 | on | 1057.728583 | 3.110375 | 1066.716500 |
| 3 | on | 1405.532500 | 2.614917 | 1411.228333 |
| 4 | off | 977.388375 | 3.014541 | 983.932959 |

The on-minus-off median of execution plus cleanup is **+110.160146 ms**.
Source setup was **207.176166 ms**, recorded separately. Each sample starts a
fresh execution process; task 1 prepares/imports the resident environment and
tasks 2/3 reuse it. All samples preserve the same expected Result CID,
selection identity, seven physical attempts and zero final held/reserved bytes.
Enabled observations additionally pass the actual Node planner/Owner admission.

This four-sample diagnostic is not a causal observer overhead bound or a
performance regression gate. Process/compile/OS caches are uncontrolled, and
the variation is substantial. Its nested phase intervals are not summed and
the difference is not subtracted from #507's separately matched Native
before/after result. It does not support a claim that observation is free or
negligible. No unfavorable sample was removed and no favorable retry was sought.

## Requirement-to-evidence boundaries

| Obligation | Evidence and limit |
| --- | --- |
| Explicit Host, actual acquisition and Compute selections | #458/#507 actual planner records; acquisition in Native is one offered candidate, not an automatic Native/Broad Host choice. |
| Two genuine Compute choices with independent expected values | Existing Native 100-row Owner settings, including Local, fresh DuckDB and resident DuckDB. Same Program/limits/expected output are admitted; control estimates are not invented selection reasons. |
| Ineligible/attempt-cap/unknown-cost behavior | Existing ten-setting Native Owner and bounded Node acquisition acceptance. Unknown costs remain unknown; feasibility/authority do not follow from low cost. |
| External-policy rejection, actual dispatch and cleanup | Strengthened source test above, through the existing neutral Owner. Network/mTLS transport is not newly verified. |
| Existing ties/revisions | Five existing JS cases, with their actual working-diff receipt retained separately. |
| Physical attempts, intermediate holding and duplicate close | Existing Native preparation/import observations and release Owner admission; no task-count equality substituted for attempt correspondence. |
| Cancellation | Existing Node process-cancel acceptance and Native between-task stop have different scopes. Neither is promoted to public Run `Cancelled` or every active-Compute cancellation path. |
| Concrete latency improvement | #507's 21 fixed alternating pairs: complete-parent mean reduction 40.771 ms, 95% interval [17.866, 65.688] ms reduction, at the stated 1,000-row Text/resident condition. All preparation and cleanup costs remain recorded. |
| Measurement load | Four fixed Node on/off observations above; no complete Native instrumentation overhead bound. |

Main has newer value/encoding work than the performance experiment. The recorded
speedup belongs to its original source/binaries and conditions; it is not a
fresh benchmark result for today's main. This supplement changes only a
whitebox acceptance test and review evidence. Whole-workload optimization,
physical heap bounds, #412 isolated-image acceptance and dynamic Hybrid/Cloud
placement remain separate work. Hosted CI remains separate from local passes;
the user performs merge.
