# Nullable object paths in aggregate arguments

## Baseline and existing contract

This independent repair starts at main
`44e07a2de522d4dfc6d7924d4672e88d237aa6e3`. It does not depend on the
pending ORDER property or grouped SELECT/HAVING repairs.

The existing [group contract](../spec/language.md) accepts a row-local
`expr` instead of a direct `field`. Its owner evaluates that expression, excludes
NULL before DISTINCT and folding, and supplies the declared aggregate output
contract. COUNT counts non-NULL values; COUNTIF counts true values. SUM/AVG
retain their numeric observation requirements. An empty global group returns
one row: COUNT is zero, while SUM/AVG/MIN are NULL. The selected
[query scope](../spec/query-text.md#scope-and-lowering) resolves SELECT arguments
against the input snapshot and keeps current Pipe columns separate from an
older range alias. The limited OVER aggregate calls share this argument boundary.

Google's [aggregate reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/aggregate_functions#count)
also distinguishes COUNT(expr), DISTINCT and COUNTIF. No Google service
differential execution was performed. This unit connects the existing selected
profile and common object contract; it does not adopt additional aggregate
clauses or claim full GoogleSQL STRUCT coverage.

## Counterexample and minimal repair

Two new tests fail on the baseline (**0/2**, `run-NqcOs9`,
`focused-test-et877z`):

```sql
SELECT COUNT(payload.score) AS n, MIN(objects.payload.score) AS m FROM objects;
FROM objects AS before
|> AGGREGATE COUNT(before.payload.score) AS n, MIN(payload.score) AS m
|> SELECT n, m;
```

`lower_aggregate_resolved` treated every reference as a direct column. A dotted
property argument therefore failed before reaching the existing common `expr`
path. Computed aggregate arguments also used the scalar-only append entry.

The repair preserves the direct-field path for a completely resolved column.
Other arguments use `append_with_properties`, with the same bounded prefix
resolution and common property expression as ordinary projections. The argument
stays inside the aggregate; no preceding derive or independent evaluator changes
its evaluation position. Common typing rejects a missing field, scalar receiver
or non-boolean COUNTIF. A displaced Pipe range remains inaccessible.

Property construction authors members in canonical `name,value` order. Aggregate
emission retains the expression's source representation, so this ordering also
lets generated arguments pass the existing canonical AoA issuance boundary.
It does not change the property's receiver, name, value, type or canonical
semantic identity, and it does not weaken that boundary's validation.

There are no checker, planner, provider, Host, wire, grammar, schema, numeric-law
or saved-data changes. Previously rejected valid text receives an ordinary
Program and its normal identity. CTE/assert/Effect assembly is untouched.

## Independent expectations

The fixture defines these six typed rows independently of the lowerer:

| ID | Bucket | Nullable payload score | Other score |
|---|---|---|---|
| 2 | A | 10 | 100 |
| 1 | A | 20 | 200 |
| 3 | A | NULL receiver | 300 |
| 5 | A | 20 | 400 |
| 6 | A | 30 | 500 |
| 4 | B | NULL field | 600 |

For bucket A, COUNT is 4, COUNT DISTINCT is 3, COUNTIF(score >= 20) is 3,
SUM is 80, AVG is 20, MIN is 10 and MAX is 30. Bucket B has zero counts
and NULL folds. Thus nullable receivers, nullable fields and duplicate values
are observable separately. After Pipe SET replaces payload with other, the
current receiver has count 6 while the prior range retains count 4. A SELECT
sibling alias named payload does not change another argument's input receiver.

The [MoonBit tests](../../src/query_program/aggregate_property_paths_test.mbt)
include a complete handwritten expected Program, check both Programs with the
ordinary checker, and compare canonical Program semantics. They also retain
numeric evidence requirements, explicit OVER frame, scope refusals, resource
work limits and original source diagnostics.

The [public fixtures](../../scripts/fixtures/aggregate-property-source-input.mjs)
contain **eight positives and four preparation refusals**. A complete handwritten
JSON control and SQL/Pipe sources use the same independently specified rows,
types and expected results. Authored text uses ordinary DATA, parameter
declarations and values; the harness never patches a lowered Program or supplies
a substitute checker. Expected column order and nullability are explicit.
The cases are registered in the normal packed corpus as well as its focused
selection. Common limited OVER argument handling has a separate public case.

## Executed and pending evidence

- Focused JS aggregate selection after canonical property construction:
  **12/12** (`run-0o5FIw`, `focused-test-AlE0y8`), comprising eight new
  and four existing tests. The preceding argument-only repair also passed
  12/12 (`run-LarSIj`, `focused-test-HVSv0m`).
- Affected shared query expression package: **8/8** (`run-zIjmj2`,
  `focused-test-i9bo8D`) after canonical property construction.
- Affected existing analytic callers: **3/3** (`run-56Pnht`,
  `focused-test-9OjQQP`). These counts are separate selections, not a claimed
  combined coverage of all aggregate or analytic behavior; this earlier caller
  selection preceded the member-order change. The new OVER property case is
  also in the final aggregate selection.
- Changed MoonBit formatting, three JavaScript syntax checks and diff checks
  pass. An initial test helper failed to compile before baseline reproduction;
  it was corrected and is not counted as a successful test execution.
- Fresh packed Embedded Local/authenticated HTTP acceptance remains incomplete. The
  selected command is `node scripts/test-packed-public-query.mjs
  --aggregate-property-only`, using normal prepack and pinned toolchains.
  It must compare Named Result values and complete ordered column contracts,
  stream completion, same-Run resubmit/attach, hidden-column exclusion and zero
  Source reads. Refusals must have zero Run admission and provider I/O.
- Submitted-HEAD required CI is separate and pending. Full Core, all targets,
  proof, native and performance campaigns are not local checks for this unit.

This does not close nested GROUP keys, HAVING property paths, non-aggregate
analytic arguments, collection-specific argument ordering or the whole Frontend.

## Separate common Values emitter finding

The first fresh packed source `fd776f1fda2a3bb249bd0d032efd0e179e778d78`
(`public-query-evidence-m3uQxC`) stopped on the independent JSON control before
any text acceptance or HTTP case. Public submission returned `SubmissionUnknown`
with a 500 `ClientHostFailure`; this was not a parse or aggregate type refusal.
The README smoke controls passed separately, not the aggregate cases. Logs and
identity/digests were retained; the disposable install was removed.

An incremental bridge probe over those compiled inputs prepared the same JSON
successfully. The Values compiler returned
`Compilation(Plan(Graph(Fragment(AoA(NoncanonicalPipeline)))))`, while the task
compiler succeeded. The emitted raw aggregate expression retained property
members in author order `value,name`; canonical order is `name,value`. At the
first mismatch, all member values were identical. This is a common single-Values
AoA emission defect, independent of text argument lowering. No Host route,
compiler guard or fallback was changed to bypass it.

The [minimal authored JSON reproduction](../../scripts/fixtures/aggregate-property-member-order.repro.program.json)
expects one row `{"n":1}`. Common preparation must accept either JSON member
order and emit the same canonical AoA identity. This boundary belongs to the
common owner: `run_publication_host::emit_client_values_pipeline_graph` and
the aggregate expression emitter called by `lowering_relation::emit_sequence_steps`.
The independent acceptance control now authors its property members in canonical
order; expressions, input rows, types, aggregate arguments and expected output
are unchanged. This does not claim the separate member-order defect is repaired.

The subsequent `53e6eaa21963352eefe593e2ace23dd2260cdbbb` probe
(`public-query-evidence-qBOC1L`) passed the JSON control, then stopped on SQL.
Temporary untracked bridge diagnostics made its tree dirty; it is a diagnostic,
not pristine source acceptance. The source preparation bridge also prepared
that SQL successfully, with one task; Values compilation hit the same member
order failure. The Frontend property builder now writes canonical member order,
while the arbitrary machine-JSON member-order issue remains a separate
common-owner handoff. The temporary diagnostic files were moved outside the checkout
before the next clean-source acceptance.

## Current public execution boundary and common-owner handoff

Clean packed source `46fa3cd853e5b95f089fa676f174476df2242c8a`
(`public-query-evidence-cC3U2r`) passed the independent JSON control through
Embedded Local Named Result rows and ordered column contracts. The first SQL
case was admitted, then ended `failed / ACTQL_E_UNPUBLISHED_RUN`. The remaining
six text positives, four preparation refusals and all aggregate HTTP cases
were not reached. README Local/HTTPS and missing-asset controls passed separately.
The receipt has no evidence errors and records disposable artifact removal,
but the failed campaign is incomplete; it is not a public acceptance pass.

A same-source diagnostic run retained its private installation
(`public-query-evidence-hPqqYM`). The follow-up uses its installed Source profile
and explicit fixture authorization. A diagnostic-only logging overlay in that
disposable installation exposed the existing execution failure; it changes no
repository Host or common owner and is not pristine packed evidence. The actual
chain was:

```text
runtimeCore.next -> strategyHostNext -> prepare_next_compute_task
NodeHostFailure.Dispatch(ComputeHostIssue.Dispatch(InstalledDispatchIssue.NoStrategy))
execution.status = host-tasks-failed
publication -> StrategyNotComplete -> CapturedRunPublicationFailed
public state -> ACTQL_E_UNPUBLISHED_RUN
```

The source preparation bridge checks this source and compiles both Values and
task plans successfully. Its graph contains one task. Candidate exclusions and
comparisons at the failure are empty; no specific rejected candidate has been
identified. This is an unresolved dispatch boundary, not proof that the capacity
budget is insufficient or that a provider kernel returned wrong rows.

The [generated Program](../../scripts/fixtures/aggregate-property-data-generated.repro.program.json)
is diagnostic product output, **not an independent expectation**. It was saved
without patching any steps, predicates, parameters or limits. Submitting exactly
that document through the public JSON input with the original parameter values
also failed at the same `Dispatch(NoStrategy)` boundary. The text parser and
lowerer were not called in this control. The six-row independent expectations
above and the public fixture remain unchanged.

For common-owner investigation, use the exported
`aggregatePropertyDataReproduction` in the [authored fixture](../../scripts/fixtures/aggregate-property-source-input.mjs).
It provides source, declarations, values, expected rows and ordered columns.
The saved Program already contains its parameter declarations; JSON submission
must pass only the separate values, without external declaration merging:

```js
const execution = await client.aql(generatedProgramText, {
  format: 'json', parameters: aggregatePropertyDataReproduction.parameters,
  requestId: 'aggregate-property-generated-control',
});
const state = await execution.wait();
```

The source reproduction command is
`node scripts/test-packed-public-query.mjs --aggregate-property-only --keep-artifacts`
at the recorded source SHA with pinned toolchains. A zero exit from a diagnostic
probe that captures this failure means reproduction, not successful execution.
The common investigation boundary is the installed strategy offer/selection for
this one-task Values/derive/append/group/sort pipeline (A/common Compute, with
the Host connection owner if needed). This PR adds no strategy, task partition,
execution owner, budget increase or fallback. No dependency fix SHA is available;
Draft remains until the original public cases pass on both transports.

| Packed package at the clean source SHA | SHA-256 |
|---|---|
| `actql-client-wire-0.0.0-development.tgz` | `2736da3e155164d87b70e54dd6eb5fdaaa711e837097149ddf730b72d1c7bf0f` |
| `actql-sdk-0.0.0-development.tgz` | `f81bf27c3bb42a007bc16b6f89a15542a89c7fb844e2893870d1161a8e8abc6d` |
| `actql-run-host-core-0.0.0-development.tgz` | `1c81124d1abef56cab7d76a72498f113e5ffcc33d4a0288830a2a18e224a1275` |
| `actql-local-node-0.0.0-development.tgz` | `b01be60a7b21696841bbc02430f4289eb3a1f3e41c68a8052f13db48414cce24` |
| `actql-node-0.0.0-development.tgz` | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Only evidence, reproduction material and an unused fixture export were added
after the tested source. Submitted-HEAD CI remains distinct and is reported in
the PR. The retained diagnostic install/Store must not be reused as an unchanged
distribution after the logging overlay.

## Integrated source preparation (2026-10-05)

Main `82d3e85e0150157ab2a3beedcf9e1e476f565b58`, including the #403
retained Relation branch provider and #399 public retained-output connection,
was normally merged at `39ba09585086ab44bedc50a49e238170d5c97f96`.
The only conflicts were the packed corpus imports/routing/selection lists.
Both sides' fixtures and focused flags are retained; main's CI policy and
common execution changes are preserved. No new common implementation or
expectation change is introduced. The PR remains independent with base main.

These commands ran at that clean integrated source with the pinned toolchain:

- `node scripts/local-checks.mjs test moon -- --target js src/query_program/aggregate_property_paths_test.mbt`:
  **8/8**, guard `run-88JfG0`, focused receipt `focused-test-hYWXZv`.
- `node scripts/local-checks.mjs test moon -- --target js src/query_expression/lower_test.mbt`:
  **10/10**, guard `run-J07PcI`, focused receipt `focused-test-uboUi3`.
- Syntax checks for the two conflicted JavaScript files and `git diff --check`:
  passed. These are integration/lowering checks, not public execution evidence.

The existing bounded selection
`node scripts/test-packed-public-query.mjs --aggregate-property-only --keep-artifacts`
was requested through the heavy-check guard, but **did not launch**. Attempt
`run-VxXGW1` refused before executing its step because another worktree's
active public acceptance held the shared heavy lock. That lock/process/output
was not removed, interrupted or bypassed. No tarballs or public cases were
produced by this attempt, and it is not a product failure.

The earlier clean `46fa3cd853e5b95f089fa676f174476df2242c8a` pack and
`Dispatch(NoStrategy)` diagnosis above are historical evidence only. The main
changes give a reason to resume the original eight positives and four
preparation refusals, but do not themselves prove the old blocker is resolved
or identify a new current-HEAD failure. Fresh integrated-source Local/HTTP
acceptance remains **unverified**, including Named rows/full ordered types,
empty aggregates, the limited OVER case, typed refusals and same-Run reuse.
The unrelated JOIN capacity diagnosis is not projected onto this Program.

No full Core, all-target, native, proof or performance campaign is added.
After the shared acceptance slot is available, use one ordinary clean-source
pack and the unchanged selection above. CI for the later evidence-only HEAD
is reported separately in the PR. No manual CI rerun or PR merge is performed.
