# DISTINCT aggregate expression input identity

Date: 2026-10-09. Owner: B. Base: `b40818e09295dba39de6b570b977610e95c75b1e`.
This is an existing Frontend contract repair, not a new aggregate execution
profile or a claim of complete GoogleSQL conformance.

## Defect and adopted meaning

The existing DISTINCT aggregate rule in `docs/spec/query-text.md` requires an
aggregate-local order expression to denote the aggregate argument in the same
input scope. Qualification, quotation and equivalent static member syntax do
not change that input. The selected [GoogleSQL aggregate-call rule](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/aggregate-function-calls)
requires the DISTINCT sort key to be the same expression. No live Google service
or broader differential campaign was run.

```sql
SELECT STRING_AGG(DISTINCT IFNULL(name, 'missing'), '|'
  ORDER BY IFNULL(objects.name, 'missing')) AS names
FROM objects
```

The independently authored complete ordinary Program passes the existing
checker. Before the repair, the corresponding source fails with the exact
`UnsupportedAggregate` cause. The root-reference fast path already resolved
physical input slots, but the computed-expression fallback only compared source
spelling. That incorrectly rejected the qualified operand inside IFNULL.

## Repair and boundaries

`query_aggregate_order.mbt` uses the existing
`same_group_expression_in_scopes` comparator for computed DISTINCT arguments
and evaluated order-key reuse. Both operands use the same immutable aggregate
input resolver. The comparator retains operators, literal values, parameter
identity, explicit receiver boundaries and static member names.

No parser, expression evaluator, total-expression admission guard, aggregate
Owner, capacity limit, wire contract, schema pin or grammar identity changes.
Existing nullable property typing and aggregate/filter demand stay with the
common checker and execution Owner. Current Pipe values and prior range
snapshots remain distinct after SET. An explicit object receiver cannot be
flattened into a range-qualified column. Potentially failing operands remain
unsupported for pre-GROUP key hoisting.

The order-key cache now shares one derive for equivalent qualifications in the
same input scope; opposite directions and NULL ordering remain independent
aggregate declarations. The aggregate argument retains its existing expression
path. This does not claim that an argument expression is evaluated only once
across all separate aggregate calls.

## Independent expectations

- Full expected Programs cover SQL/Pipe IFNULL, backtick/case qualification,
  nested static members and one shared order derive for opposite orders.
- Exact `UnsupportedAggregate` regressions retain different fields, fallback
  literals, operators, parameter names, SET snapshots and object/range receivers.
- The two-alias cache fixture initially reserved private slot 5 incorrectly.
  `pipe_physical_name` starts at the reserved-name count: four input fields plus
  two output aliases require slot 6. Only the independently designed private
  name was corrected; expressions, columns, bounds and ordering were retained.
- Existing public fixture registration includes new cases in both normal
  acceptance and the existing aggregate-property-order selection. JSON control
  Programs are handwritten, never copied from compiler/runtime output.
- Duplicate b rows plus a/c/NULL produce `a|b|c|missing` under DISTINCT;
  ordinary opposite-order calls preserve `a|b|b|c` / `c|b|b|a`.
- A keyed, bounded ARRAY_AGG of IFNULL(payload.score,0) produces `[20,10,0]`
  descending, retaining the actual unique_by assertion and LIMIT 4. Empty
  STRING_AGG returns a nullable string with SQL NULL.
- Public refusals retain exact implementation-limit classification for
  mismatched DISTINCT keys; the public harness checks no Run admission/provider
  acquisition. Normal success checks retain Named Result rows, describe types,
  column order, hidden-field exclusion and one Source acquisition.

## Focused evidence

All commands use pinned Node 22.22.0 / MoonBit 0.10.12+1634b282e and the existing
bounded/nonzero-test wrapper. Local evidence IDs are retained under the owned
worktree's ignored `_build` directories; they are not CI runs.

- Initial pre-repair comparison: `run-gsqczg`, 0/1 (unwrapped refusal).
- Exact pre-repair cause: `run-nDx19j` / `focused-test-P9WcBx`, 0/1,
  `UnsupportedAggregate`. An intermediate diagnostic helper compile failure
  (`run-HboWW7`) did not execute tests and is not acceptance evidence.
- First repaired selection: `run-LqIs7V`, 28/29; only the independent cache
  private-name reservation differed, as explained above.
- Final focused JS: `run-8YojWx` / `focused-test-eyHUvN`, **29/29**.
  Command: `node scripts/local-checks.mjs test moon --timeout-seconds 240 --
  --target js src/query_program/distinct_aggregate_expression_scope_test.mbt
  src/query_program/distinct_aggregate_order_test.mbt
  src/query_program/aggregate_conditional_order_test.mbt
  src/query_program/aggregate_member_call_reuse_test.mbt
  src/query_program/aggregate_order_parameter_test.mbt
  src/query_program/group_property_receiver_scope_test.mbt`.
- Node fixtures: `run-ibp7bf` / `focused-test-5TZO1q`, **9/9**.
  Command: `node scripts/local-checks.mjs test node --
  scripts/aggregate-conditional-order-source-input.test.mjs
  scripts/aggregate-property-order-source-input.test.mjs`.
- Changed MoonBit files were formatted and `git diff --check` passed.

## Public acceptance and remaining verification

Verified clean source: `b5bfb7b926bb63ed4d678f98f6fcedd63fcb5f02`.
Normal five-package producer, independent digest verification and the existing
`node scripts/test-packed-public-query.mjs --aggregate-property-order-only`
consumer completed through the bounded heavy-slot wrapper, `run-H8iFAu`.
The source and fixture inputs remained clean throughout. No adapter overlays,
manual Program repair, skipped prepack or mixed-revision runtime was used.

Each Embedded Local and HTTPS entrance completed **72 positive cases, 36
pre-admission refusals and one expected demanded-argument execution failure**.
Both entrances reached Named Result rows and describe columns; the standard
harness verified source acquisition counts, reattach/read/resend without new
Run or I/O, and exact refusal codes for the four new mismatches. All eight new
positive fixtures ran on both entrances, including two independent JSON
controls. These counts describe the selected aggregate cohort, not every
Frontend feature. The driver's 14 profile checks, README Local/HTTPS example
and missing-generated-asset refusal also passed. No fresh-process aggregate
recovery campaign was selected.

Receipt: `public-query-evidence-Uqzl1K`, retained in the worktrees'
`.codex-scratch` evidence directory. It records exact clean source, all command
statuses, stdout/stderr and five tarball digests; final status `passed`,
`complete: true`, `evidenceErrors: []`. The transient external installation was
automatically removed after retaining evidence (`artifactsRemoved: true`). The
normal producer artifacts remain in the owned external pack directory
`actql-b-distinct-aggregate-scope-pack`, with the source/digest manifest.

| Package | SHA-256 |
|---|---|
| client-wire | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| sdk | `c468fa4d31016b3d10539f1edc49a113241a52a67d34493ff165bfac30ed102c` |
| run-host-core | `332a770a589f74f697fca8427c364da9b89dfc23c3fea9a1bd7c59c5d0e0401d` |
| local-node | `5d18f4ee79078884930b455ef738f09613091caf7b11d09fbb64b2f248029a8d` |
| node | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

The evidence-only follow-up commit does not change compiler, runtime, fixtures
or generated inputs. Packed evidence applies to the clean source SHA above;
it is not relabeled as execution of the submitted HEAD. Required CI for that
HEAD remains unverified. Full Core, Wasm/native, proof/performance and unfiltered
packed campaigns were not run locally. This unit has no unmerged dependency
and does not complete the whole Frontend coverage goal.
