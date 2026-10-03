# Frontend counterexamples: common execution capacity handoff

## Ownership and evidence status

A owns investigation and any common capacity repair; D repeats the public
acceptance after A provides a fixed source. The Run execution ceiling remains
536,870,912 bytes (512 MiB). B does not change coefficients, logical ceilings,
providers or reservation enforcement. Zero existing reservation does not imply
that a new attempt fits. These measurements establish rejection, not a defect
in the common capacity derivation.

The original three failing examples are preserved below. One is now closed by
a separate Frontend repair; the two Group examples remain unresolved. Do not
reclassify old failures as successful runs or weaken their expectations.

| Example | Clean packed runtime source | Task | Retention allowance | Required execution reservation | Already reserved execution | Observation |
|---|---|---:|---:|---:|---:|---|
| Rebound DISTINCT ORDER | `b8aa2eecaf105bb88bcbafbdc4dad2a1a48c6d95` | 1 | 14,240,000 | 572,045,056 | 0 | `Execution(Physical(ExecutionLimit))` |
| Original grouping key | `4c0f7a1e6d93533569e877d3db6d75a9003d6c4a` | 0 | 14,240,000 | 550,139,392 | 0 | Same refusal |
| Current grouping key | Same Group source | 0 | 14,240,000 | 626,696,448 | 0 | Same refusal |
| Unchanged DISTINCT expression control | Same ORDER source | 1 | 14,240,000 | 418,930,944 | 0 | Publishes expected Result |

Numbers are bytes, not heap/RSS or measured allocation maxima. The diagnostic
reads the prepared task capacity and existing official strategy usage before
managed start. The private installation's temporary diagnostic logging was
restored to its exact installed bytes. This diagnostic is not public acceptance.

## Source, actual lowering and independent expectations

The [fixture directory](fixtures/frontend-capacity/) preserves each minimal
`.aql` source and the normal checker's semantic Program getter output as
`.actual-program.json`. The latter is observed lowering, **not** an expected
Program or an oracle. The separate [expected results](fixtures/frontend-capacity/expected-results.json)
are independently authored from the adopted scope rules. All sources explicitly
declare `RESULT answer`; no ordering is removed.

- `order-rebound-distinct`: duplicate input IDs 1,2,1; selected IDs -1,-2;
  distinct output ordered by the negate of the evaluated output ID. Expected
  `[{"id":-1},{"id":-2}]`. Acquisition uses the published `records` alias.
- `order-control-distinct`: the SELECT output is named `score`, so `ORDER BY
  -id` retains its input-reference meaning and reuses the original negate.
- `group-snapshot`: inline 7/9, immutable `before.x` retains 7 after `SET x=y`;
  expected `[{"x":7,"n":1}]`.
- `group-current`: same input, current `x` is 9; expected `[{"x":9,"n":1}]`.
  Both Group cases use no external Source. Column order is `x,n`, both
  non-nullable numbers, and COUNT is 1.

Preparation of these saved Programs succeeds through the normal Frontend and
common checker. Their failing execution observations come from source input,
not a separate JSON replay. A should also run the saved Programs through the
ordinary JSON entry with the same published environment to separate common
execution from Frontend-only behavior. This JSON comparison is not yet executed.

## First failure and source-level capacity chain

`adapters/local-node/strategy-bundle.mjs::runPrepared` calls
`strategyModule_local_ManagedStart`. The first issue is
`Execution(Physical(ExecutionLimit))`, before any task completes.
`StrategyNotComplete`, capture publication failure and
`ACTQL_E_UNPUBLISHED_RUN` are later symptoms.

Source inspection at the fixed Group revision gives this chain:

1. `client_local_host/captured_ledger.mbt::client_local_sequence_capacity`
   uses the checked task inventory. It sums retained allowances, takes maximum
   execution allowance across sequential sequences, and retains the fixed Run
   ceiling. This is already a maximum, not a sum of sequential execution peaks.
2. `execution_relation/execution_capacity.mbt::generated_sequence_capacity`
   derives retention 14,240,000 and base scratch 32,531,200 from the existing
   bounded row/input/output/measurement envelopes. It adds the maximum fragment
   allowance across `generated.contexts`:
   `live_value_bytes * 264 + (body_nodes + body_depth) * 256 + body_bytes * 8`.
   The observed total less base scratch is respectively 539,513,856;
   517,608,192; 594,165,248 bytes for the original three failures. These
   differences do not reveal which individual context supplied the maximum.
3. `physical_strategy/task_execution.mbt` preserves transfer, retention,
   scratch and execution allowances from the prepared managed execution and
   calls `physical_resources/ledger.mbt::reserve_attempt` before starting it.
4. `reserve_attempt` rejects execution greater than ceiling minus current
   reservation before mutating usage. Initial strategy usage is all zero in
   the diagnostic. Lowering the coefficients without a sound upper-bound
   derivation would weaken this admission rule.

Remaining investigation belongs to A: identify the maximum context for each
selected task, its upper-bound source and units, retained input/output holding
lifetimes, scratch and transfer lifetimes, and permitted concurrency. Selected
step/prefix views retain the generated context inventory; establish whether
each charged context is actually reachable before classifying overestimation.
Verify that already retained values and output holding are neither missed nor
counted twice, and that serial lifetimes are not unnecessarily combined. Do not
substitute these small fixture sizes or measured RSS for declared upper bounds.

If the derivation is sound, keep refusal and propose separate within-budget
acceptance and over-budget refusal cases with the same semantic obligations.
The current expected values and order are not silently changed by this handoff.

## Closed Frontend-only follow-up and outstanding acceptance

[#286](https://github.com/actql/actql/pull/286) removed an unobservable duplicate
scoped ORDER cleanup projection when an immediately adjacent RESULT already
performs that same projection and binds its checkpoint. It changes no common
capacity formula or ceiling. Clean source
`06256fe791f85e7dbe4f6c71ea69bb0054e6b0fb` passes all four positives and one
refusal on both packed Embedded Local and HTTPS, including the unchanged
DISTINCT collision fixture. No new capacity number was measured. The original
572,045,056-byte refusal is historical evidence, not a remaining failure of
that follow-up source.

[#287](https://github.com/actql/actql/pull/287) remains Draft. Its SET/DROP SUM
and two scope refusals pass on both packed transports; the ordered original
and current grouping-key examples above have not published. The broader Group
fixture's later cases remain unexecuted. D should use the same ordinary public
path after A's fixed SHA, checking rows, ordered full describe contracts,
stream completion and acquisition/retry counters.

Reproduction uses each pinned clean source and its ordinary producer/prepack,
with the repository-pinned toolchain. Reuse verified tarballs across consumers
of the same source; do not rebuild unrelated Core campaigns:

```sh
node scripts/test-packed-public-query.mjs --scoped-order-only
# Run on the Group repair source, independently of the ORDER branch:
node scripts/test-packed-public-query.mjs --group-scope-only
```

The full Group selection stops on the original-key refusal. To inspect the
current-key control independently, use the same existing public acceptance
application with just that saved fixture selected; do not introduce another
executor. Historical Group pack: local-node SHA-256
`1f34d7a31024b97bf4f49efe4e3b7c7abd4679902e9ab286df761504da3d1dcc`;
historical ORDER pack:
`9cee7aa86af955a88d1e30f5a3712a8b676aff1803463f2cdbc3dc4b488c6ba1`.
Other package digests and the full executed scope are recorded in each repair
PR's evidence document. This handoff adds no execution owner, common repair,
fallback or ceiling change.
