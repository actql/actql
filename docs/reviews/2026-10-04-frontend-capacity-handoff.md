# Frontend counterexamples: common execution capacity handoff

## Ownership and evidence status

A owns investigation and any common capacity repair. B will finish #287's
remaining public cases after adopting A's fixed source; D can reuse this
handoff for the shared execution boundary without duplicating B's corpus.
The Run execution ceiling remains
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
   This is the base sequence allowance, not the complete managed provider
   reservation. Subtracting base scratch from the observed managed total does
   **not** isolate a fragment peak: chain child holding and the dispatch copy
   allowance must also be included. The earlier subtraction-only inference is
   superseded by the component calculation below.
3. `connectors/local/selected_relation_provider.mbt::bounded_relation_chain_capacity`
   sums each selected child's retention plus execution allowance, then adds
   256 bytes per child handle. Child views keep the original context inventory.
   The chain retains started children until reverse-order parent cleanup, even
   though it advances one child at a time.
4. `connectors/local/driver/managed_dispatch.mbt` adds the parent output
   retention and any imported-input retention to provider execution capacity.
   `physical_strategy/task_execution.mbt` preserves transfer, retention,
   scratch and execution allowances from the prepared managed execution and
   calls `physical_resources/ledger.mbt::reserve_attempt` before starting it.
5. `reserve_attempt` rejects execution greater than ceiling minus current
   reservation before mutating usage. Initial strategy usage is all zero in
   the diagnostic. Lowering the coefficients without a sound upper-bound
   derivation would weaken this admission rule.

### Group component calculation at the fixed source

Source inspection at `4c0f7a1e6d93533569e877d3db6d75a9003d6c4a`
accounts exactly for both recorded Group reservations. This is an arithmetic
cross-check against source and observed totals, not a new execution or proof
that the allowance is tight. Both saved Programs are source-free, so imported
input retention and transfer are zero.

| Component | Calculation | Bytes |
|---|---|---:|
| Child retained output | `(10,000 + 10,000 + 20,000) * 256 + 500,000 * 8` | 14,240,000 |
| Child base scratch nodes | `(10,000 + 10,000 + 100 + 20,000 + 20,000 + 20,000 + 100) * 256` | 20,531,200 |
| Child base scratch text | `(500,000 + 500,000 + 500,000) * 8` | 12,000,000 |
| Fragment live roots | Compute-stage live ceiling `100,000 * 264` | 26,400,000 |
| Fragment physical traversal | `(10,000 + 100) * 256 + 100,000 * 8` | 3,385,600 |
| Child execution | Base scratch plus maximum fragment allowance | 62,316,800 |
| Child holding plus execution | `14,240,000 + 62,316,800` | 76,556,800 |

The saved original-key Program contains seven steps (VALUES, literal derive,
public input projection, SET derive, group, sort, Result projection); the
current-key Program has eight, adding the post-group key-name projection.
Single-step views retain both derive contexts; even children without an
expression context of their own receive the same base fragment ceiling in the
current capacity calculation. The selected row, VALUES and group providers
delegate their child allowance to the same sequence-capacity function.

| Program | Chain children plus handles | Parent output copy holding | Imported input | Total managed execution |
|---|---:|---:|---:|---:|
| Original key | `7 * 76,556,800 + 7 * 256 = 535,899,392` | 14,240,000 | 0 | 550,139,392 |
| Current key | `8 * 76,556,800 + 8 * 256 = 612,456,448` | 14,240,000 | 0 | 626,696,448 |

The observed difference, 76,557,056 bytes, is one extra child allowance plus
one handle. It is not evidence that the rename projection can simply be
deleted. Check whether the complete fragment inventory needs charging in
every child and whether scratch remains live after a child completes. The
actual reverse cleanup retains children and borrowed completion readers; any
tighter bound must account for those lifetimes and cancellation, rather than
replace the sum with a maximum without proof.

### B's lowering review and separate expectation repair

At submitted #287 HEAD `d1d98c5414872bca35a6f3ec5182c211f269f81e`,
the original-key Program already has group → sort → one Result projection.
There is no adjacent duplicate ORDER cleanup projection like the defect fixed
in #286. In the current-key form the intervening projection renames the
evaluated SET slot to the visible group key `x`; following ORDER and Result
read that new output scope. B has not established a redundant operation that
can be removed while preserving evaluation, failures and the checkpoint
contract. Do not drop the authored SET just because this fixture's original
key does not consume its output.

The independent complete SQL/Pipe expectations added at that HEAD close the
obsolete Program-equality assertion only. They retain predicate, COUNT, key,
column order and ORDER while describing each form's own projection placement.
They do not close capacity refusal. Automatic
[CI run 37162983732](https://github.com/actql/actql/actions/runs/37162983732)
for that HEAD uses merge tree `6011bb1fcc48305e7351ea8dbf3cf86df542f8bc`.
Its packed artifact again records `group-snapshot-original-key` ending with
`ACTQL_E_UNPUBLISHED_RUN`; the preceding two SUM cases pass, but subsequent
Group cases and HTTP are not reached. This CI artifact records the publication
symptom; the earlier fixed-runtime diagnostic identifies capacity as the first
failure. The independent-Program distribution job passed on that submitted
HEAD. The packed job and its Client aggregate failed; other CI jobs were still
running when this record was made. Distribution success and public execution
failure are separate evidence.

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

## Integrated capacity follow-up: selected public acceptance closed

A's #295 is now in the integrated main baseline
`5caeccc79dacc758afa5d87c2cee6be024e32565`, through merge
`2a74d07fef4ce4e58e4d35d72039f982ddf66f26` (repair commit
`46654bbed4f6740cb49f3a89d1f60b2cdcdd5a5a`). #287 adopted that main normally.
The 512 MiB ceiling, independent expectations and declared ordering were not
changed.

Normally packed clean source `508cbeccc8826c24eb0c8efc74c0d64168c64a35`
passes all 8 positives and 4 refusals on **each** of Embedded Local and HTTP,
including the formerly refused original/current grouping keys and later
SQL/Pipe/empty/shared-source cases. This confirms Named Result rows, ordered
full type/nullability contracts, complete streams, shared acquisition counts,
same-Run retry and no I/O on re-read; input refusals precede admission/I/O.
No later failure was found in that selected Group corpus. Package digests and
the submitted report-only delta are recorded in the
[Group evidence](https://github.com/actql/actql/blob/6ee85f358bf3dabbf8d9d983b344638284df98ee/docs/reviews/2026-10-03-group-column-scope.md).

Submitted HEAD: `6ee85f358bf3dabbf8d9d983b344638284df98ee`.
[Automatic CI 37167483900](https://github.com/actql/actql/actions/runs/37167483900)
completed successfully, including client-packed, client, pipeline-evidence and
final check. #287's body now records the final result and Draft is removed for
re-review; no merge was performed. The old byte totals and failed CI below are historical observations,
not current failures or new measurements. B made no common capacity formula
change. The separately reproduced CTE shared-capture predicate defect remains
D-owned and is recorded in the [audit](2026-10-04-frontend-semantic-audit.md);
successful Group acceptance does not close it.

## Historical Frontend-only follow-up before the capacity repair

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
fixture's later cases remain unexecuted. B will use the same ordinary public
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
