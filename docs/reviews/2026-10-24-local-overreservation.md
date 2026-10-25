# fix(local): derive tighter independent transport capacity for small scalar DAGs

Priority: **P1**. Issue-ready report only; no issue was posted.

## Scope and reproduction

Base source: `f74d8e6436f314092b412669ba1281d246b604a4`, with the corrected scalar-capacity patch in `syntax-matrix-impl-relational`. These are source-runtime diagnostics, not packed release acceptance.

```sql
SELECT x FROM (
  SELECT 1 AS x UNION ALL SELECT 2 AS x
  UNION ALL SELECT 3 AS x UNION ALL SELECT 4 AS x
) ORDER BY x
```

Expected: four rows `[{"x":1},{"x":2},{"x":3},{"x":4}]`.
Actual: `check(...,{kind:'text',format:'sql',scope:'bound_input'})` reports `verified`, but ordinary `.sql(query).all()` rejects with `SubmissionNotAccepted`. The corresponding three-term query succeeds with its three expected rows. This is an admission refusal, not a successful query with truncated or incorrect rows.

Reproduction and raw results: `relational-overreservation-public.mjs`, `relational-overreservation-public.log`.

## Exact quote, not operating-system memory

The test calls the original preparation, schema-derived value-limit and retention-capacity owners. The required retained inventory is `tasks*(provider+export) + input_ports*import`; repeated ports remain separate. No production ceiling is changed.

| Query | Tasks / ports | Scalar node envelope | Before patch retained quote | Corrected retained quote |
|---|---:|---:|---:|---:|
| Original three-term ORDER/OFFSET | 14 / 13 | 3,100 | 549,884,544 B | 444,969,344 B |
| Original three-term GROUP/HAVING | 14 / 13 | 3,400 | 549,884,544 B | 446,831,744 B |
| Original three-term AQL multistage | 16 / 15 | 3,800 | 631,660,288 B | 516,575,488 B |
| Four-term ORDER reproduction | 17 / 16 | 3,800 | Not separately measured | **550,205,760 B** |

The unchanged retained ceiling is **536,870,912 B**. For the four-term reproduction, per-task provider/export allowances are 10,092,800 / 2,028,608 B and each input-port allowance is 21,508,864 B. Their exact sum exceeds the ceiling by 13,334,848 B, matching the refusal. The scalar quote still uses a 100-row ceiling even for these tiny constant queries.

These numbers are conservative **logical capacity quotes**, not measured RSS, physical allocations, or a claim that every byte is live. The separate 512 MiB execution limit is a ceiling, not observed execution usage. Concurrent-client peak memory and runtime release timing were not measured in this audit.

Evidence: `relational-capacity-quotes.log`, one focused test passed. Its fixture source `src/client_local_host/scalar_capacity_quote_wbtest.mbt` is a baseline-only diagnostic with the baseline environment identity; do not copy that fixture unchanged into an integrated profile revision.

## Exact accounting proof for the regression correction

The first patch incorrectly counted scalar cells without their row containers and did not include actual Step input ports. This caused failures at apparently surprising row counts: 51 one-column rows need 102 nodes, not 51; two input ports each independently consume their row envelopes. The correction has no special-case row thresholds.

`src/execution_relation/scalar_capacity_accounting_wbtest.mbt` directly advances the production binary scanner and reads its actual `budget.nodes`. It covers rows `0,1,25,26,49,50,51,99,100` and widths `1,2,4`, including nullable scalar cells and two independently charged ports borrowing the same producer. For every combination:

- Exact scanner usage is `2 * rows * (width + 1)`.
- The exact budget succeeds; one node less fails with `ValueLimit` (zero is handled separately).
- Scanner-owned workspace returns to zero; both borrowed producer reads remain available.
- Bare row-array wire identity consumes `1 + rows*(width+1)` nodes.
- Logical Relation identity consumes `3 + rows*(width+1)` nodes.
- Each wire identity succeeds at the exact node bound and rejects one below it.

The value specialization conservatively counts row containers and all original input occurrences, including Step references and repeated ports, and cumulative outputs across kernels plus potential external producer projections. Unknown contracts or products exceeding the original generic envelope fall back unchanged. The direct test checks the real scanner/encoder, not an oracle copied from public query output.

Evidence: `relational-exact-accounting.log`, focused test passed. Public boundary comparisons and fanout/no-partial-publication checks are reported separately by the coordinating agent.

## Remaining over-reservation and safe follow-up

There is still substantial conservative allowance. Each import port reserves `64 * wire.max_nodes`; with the generic 100,000-node bound this component alone is 6,400,000 B per port (83,200,000 B for the first query). Fixed text allowances contribute 4,000,000 B per provider and 4,000,000 B per import port: 108,000,000 B for the first query and 124,000,000 B for the pipe query. Those text limits also govern expression intermediate work and field-name processing, so zeroing them for scalar relation schemas is not justified.

For the narrowly proven scalar schema branch, replacing only the import wire-node component with `value_nodes + 3` would algebraically save 80,618,304 B for the ORDER/OFFSET case and 92,349,120 B for the pipe case. **This is a potential saving, not an implemented or accepted configuration.** The wrapper allowance is `+3`, not `+1`, because the same transport policy also participates in the logical Relation envelope.

Before changing the transport bound, separate or prove all its current consumers:

1. `client_local_host/host.mbt`: import/export policy construction must select identical original bounds for quote and execution.
2. `connectors/local/materializing.mbt`: retained import capacity and producer-output import.
3. `connectors/local/driver/managed_dispatch.mbt`: the same `wire.max_nodes` is reused as bridge/completion **max_entries**, and as schema-identity/node limits; it is not exclusively a wire-encoding bound.
4. `execution_relation/managed_producer_bridge.mbt` and `managed_completion.mbt`: prove metadata/provenance requirements independently of value-node counts.
5. `execution_relation/completed_relation_identity_scan.mbt`: preserve simultaneous payload/logical writers and schema/row ownership; logical wrappers and workspace overlaps cannot be omitted.
6. Keep original byte/text/intermediate limits and cancellation ownership; rerun exact-boundary, missing-schema/fallback, duplicate-port, nullable, fanout and controlled-failure/no-publication tests.

A subsequent optimization should use original checked schema/row evidence, not observed successful rows, and should demonstrate that the four-term reproduction executes without increasing the ceiling. It must retain conservative safety for arbitrary expressions whose final relation schema is scalar. This report intentionally does not attempt that broader rewrite.
