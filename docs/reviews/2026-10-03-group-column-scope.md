# Aggregation column scope: Frontend connection

## Current integrated acceptance

Main `5caeccc79dacc758afa5d87c2cee6be024e32565` was normally merged, including
A's #295 selected-fragment capacity repair and D's #273 composition connection.
The only merge conflict was the packed consumer selector; both the existing
scoped-order selector and this grouping selector were preserved. The grouping
flag now also skips unrelated planner, two-source, String restart and native
campaigns. No expected Program/row, Source predicate or 512 MiB ceiling changed.

Verified clean packed source:
`508cbeccc8826c24eb0c8efc74c0d64168c64a35`.
`node scripts/test-packed-public-query.mjs --group-scope-only` passed all
**8 normal cases and 4 refusals on both Embedded Local and HTTP**. The original
key/current key cases now succeed. Computed SQL grouping alias, Pipe JOIN scope,
typed empty input and acquired shared producer also succeed; no later CTE
failure was observed in this selected corpus. Shared Source acquisition remains
one session, and duplicate id=3 produces count 8. The existing harness verifies
Named Result rows, describe column types/nullability/order, stream completion,
same-request Run reuse and refusal before Run admission/provider I/O.

The independent SQL/Pipe Program correction and the former common capacity
refusal remain separate historical findings. #295 resolves the latter for these
fixtures without changing their expectations. The focused JS grouping selection
also passed 5/5 on this integrated source. Full Core/all-target/proof/performance
and full packed suites were not rerun locally. Exact submitted-HEAD automatic CI
remains separate; earlier failed CI is not relabelled as success.

Evidence invocation `public-query-evidence-e1c6Be` completed/passed and records
SHA, command statuses, logs and digests. Its owned installation was cleaned after
preserving evidence (`artifactsRemoved: true`). These are current tarballs;
previous tables below retain their historical source identities:

| Package | SHA-256 |
|---|---|
| actql-client-wire-0.0.0-development.tgz | `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0` |
| actql-sdk-0.0.0-development.tgz | `2fc910067348e421346945ced1e728e107bbe6fa455ee00f9d71da46e8123c5b` |
| actql-run-host-core-0.0.0-development.tgz | `58b020ac54fab05b0ef6336111cf85f6311b243195d1862d8bf46cd62fa77daf` |
| actql-local-node-0.0.0-development.tgz | `dee3b5f53d1192a3b737a4f6cd41d657edef9051a8fe0cc57733c8557a01edbe` |
| actql-node-0.0.0-development.tgz | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |


## Baseline and dependency

This repair now starts from main
`a4132d64f9cd83022d38bcb9c4e79d981fb2f803` on
`fix/frontend-group-input-scope`. #266 is already merged; there is no unmerged
JOIN parent. The earlier implementation commits were retained and reapplied to
this fixed baseline without rewriting published history.

The assertion, terminal Effect, Source predicate and JOIN-limit locations for
#273 remain D-owned. This unit changes aggregate input/output scope only;
there are no declaration, validator, workflow or common execution-owner changes.

## Existing semantics and implementation defect

The adopted [column scope](../spec/query-text.md#scope-and-lowering) and
[vocabulary criteria](../design/semantic-decisions.md#vocabulary-across-representations)
separate input range bindings, current Pipe columns and SQL output aliases.
SQL GROUP BY/HAVING applies the existing SELECT-alias rules. Pipe AGGREGATE
consumes the old input scope and produces only its grouping columns and named
aggregates; dropped input ranges do not reappear after it.
Google's [Pipe AGGREGATE reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/pipe-syntax#aggregate_pipe_operator)
also specifies grouping columns before aggregate columns. Its wider support
for grouping-item aliases, grouping sets and scalar expressions around
aggregates is not established by this unit's simple-key fixtures.

The previous scoped path projected current columns to their displayed names
before resolving GROUP BY and aggregate arguments. This discarded qualified
JOIN bindings and the original value retained by a Pipe alias after SET.
It could also try to project several JOIN inputs' same-named columns into one
ordinary Relation schema. These are lowering defects, not new restrictions on
the adopted language or missing common group semantics.

The parser now retains `GroupingScope::SqlSelect` or
`GroupingScope::PipeAggregate` on its common Group operation. That metadata
survives the defensive query accessor. It changes the Frontend AST interface,
not Program/wire/schema versions, a scalar type or the common group operation.
The generated interface is regenerated from source.

The lowerer resolves keys and aggregate arguments against the existing physical
slots. It does not materialize the entire displayed row first. SQL retains only
grouped input bindings until SELECT, supports HAVING through those bindings,
and reuses an already evaluated grouping expression. Pipe creates its new scope
after grouping and projects retained private key slots to the authored column
names. Its old ranges remain inaccessible with or without a preceding SET.

For the independently authored input `[{"x":7,"y":9}]`, after `AS before`
and `SET x = y`, current x is 9 while before.x is 7. Grouping by before.x
with SUM(x) and SUM(before.x) must reference three actual slots: original x,
the SET slot, and original x. The complete independent Program is in
[the regression tests](../../src/query_program/group_scope_test.mbt).
SUM still requires the ordinary common numeric profile; missing evidence stays
NeedsInputs. No Frontend evidence, alternate evaluator or runtime is introduced.

## Independent public acceptance target

[Eight positive/four refusal fixtures](../../spec/frontend/fixtures/group-scope/cases.json)
are authored from the selected semantics, not compiler output. They cover:

- Original SUM argument after SET and DROP: input IDs 1/2 sum to 3,
  rather than the changed values 10/20. SUM remains nullable by common contract.
- Original versus current key after SET: x=7 versus x=9, each with count 1.
- Computed SQL grouping alias, HAVING and ordered output through three JOINs.
- Pipe JOIN grouping followed by its new public x/n scope.
- Empty nullable grouping input with complete column contracts.
- One acquired producer reused by three JOIN inputs: counts 1, 1 and 8 for
  ids 1, 2 and 3, with one source acquisition session.
- Refusal of old ranges and ungrouped/dropped columns before Run admission/I/O.

The existing external-installation driver consumes the same fixtures on Local
and HTTP, including Named Result rows, full descriptions, attach, resubmission
and unchanged counters. Both the default corpus and the narrow selector use
the normal package producer and common Host:

```sh
node scripts/test-packed-public-query.mjs --group-scope-only
```

Before the #295 integration above, the entire eight-positive/four-refusal corpus had **not passed**. The original
Local run passed the two SUM cases, then stopped at
`group-snapshot-original-key`; HTTPS was not reached in that run. No prior
#246 JSON composition result is used as text execution evidence.

## Historical pre-capacity-fix evidence

On the current baseline with the reapplied repair, the selected Group, JOIN
ORDER and query parser tests passed 28/28 on JS before adding the two global
SUM counterexamples. After adding the global SUM cases, Group and Pipe scope tests passed 11/11
on JS.

Clean packed source: `4c0f7a1e6d93533569e877d3db6d75a9003d6c4a`.
Normal package producer/prepack and external installation succeeded. Reusing
these verified tarballs, two positive cases (original SUM after SET and DROP)
and two refusals (old range after aggregation and a dropped non-grouped input)
passed on **both Embedded Local and HTTPS**. The existing helper verifies exact
rows, full column contracts and order through describe, stream completion,
same-request resubmission, attach, one acquisition session and no reacquisition.
The refusal checks preserve zero Run admissions and provider I/O. This follow-up
selected cases and isolated test directories from the existing application;
the installed runtime was byte-checked against its tarball.

The remaining original-key/current-key grouping cases fail during
`strategyModule_local_ManagedStart` in
`adapters/local-node/strategy-bundle.mjs::runPrepared`, with
`Execution(Physical(ExecutionLimit))`. A cause-tracing diagnostic on the recorded
runtime confirmed that both forms reach this same first failure; no task
completes. The later `StrategyNotComplete` and `ACTQL_E_UNPUBLISHED_RUN` do not
identify the root cause. This diagnostic temporarily logged an existing error
cause in the private installation and restored its bytes. It is not successful
runtime acceptance. The expectations x=7 and x=9, and explicit ORDER BY, remain
unchanged. No Host ceiling, owner, provider or physical strategy is changed here.

The later JOIN/empty-input/shared-producer public cases remain unexecuted.
The automatic CI for submitted `e1366724e05e1296e06f7678eb28ef745fc2eaa8`
([run 37160787074](https://github.com/actql/actql/actions/runs/37160787074))
completed unsuccessfully. Its packed artifact independently records failure
of `group-snapshot-original-key`; later cases and HTTP were not reached.
Distribution also stopped on an obsolete byte-equality assertion between SQL
and Pipe grouping Programs. The two forms retain the same predicates, COUNT,
key, output columns and ORDER, but have different projection/checkpoint placement.
The distribution comparison now checks each against its own independently
authored complete machine Program, instead of using one product output as
another's expectation. The new narrowly selected Node test passes 1/1 after
building only the JS test bridge. An initial authored fixture used the wrong
Result-reference key `name`; it was corrected to the existing Program contract's
`result` key, and that failed invocation is not a product defect or a pass.
Full distribution acceptance has not been rerun locally.

The two capacity refusals have been assigned to A for common-boundary
investigation and D for subsequent public reacceptance. See the fixed
[capacity handoff](https://github.com/actql/actql/blob/10273f0d08ccaf8d0b833432ccfca8a68451a385/docs/reviews/2026-10-04-frontend-capacity-handoff.md)
for minimal source, actual checked Programs, independent rows, 550,139,392 /
626,696,448-byte reservations and the untouched 536,870,912-byte ceiling.
No overestimate is proven yet. This is a lowering repair with representative
public acceptance, not completion of the full grouping corpus.

### Recorded package SHA-256

Names have suffix `-0.0.0-development.tgz`. The limited Local/HTTPS checks reuse
these artifacts from the clean packed source above.

| Package | SHA-256 |
|---|---|
| actql-client-wire | `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0` |
| actql-sdk | `2fc910067348e421346945ced1e728e107bbe6fa455ee00f9d71da46e8123c5b` |
| actql-run-host-core | `901be13bedaeb53a23f7e16af1a930c9eac313c828fdc227eedfd4d66ff1f898` |
| actql-local-node | `1f34d7a31024b97bf4f49efe4e3b7c7abd4679902e9ab286df761504da3d1dcc` |
| actql-node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

The original audit at runtime `ba3d6d12891f884b1bb55bb4d67bf043d4a58a94`
rejected the SET and DROP SUM counterexamples before admission/provider I/O,
while unqualified SUM of the current SET value succeeded. The relevant Group
source is unchanged between that revision and this baseline. This is a source
comparison, not a current-baseline execution reproduction.

## Historical focused evidence (not current-baseline validation)

The changed group tests plus existing compile/JOIN tests passed 73/73 on JS.
After adding the complete independent Program assertion, selected group/parser
tests passed 20/20. The initial SUM test correctly returned NeedsInputs without
the numeric profile; the corrected test asserts that requirement before checking
with the existing declared profile. That initial failure is not counted as a
successful test or a removed common check.

The new parser metadata/accessor regression passed 17/17 with the existing
parser cases after correcting its test-only constructor qualification. Changed
Node scripts pass syntax checks; document links and whitespace are checked
separately. None of those checks executes the prepared public fixture rows.

At integration `a2659718d18265b1359339293294fff277aa7ee8`, the selected
grouping test file passed 5/5, including a loop over all six authored positive
sources through script lowering and ordinary admission/checking. The acquired
input was represented by Values in that focused test; this does not establish
source acquisition or public Host execution.

A separate one-case Local JSON control passed using the unchanged installed
packages from source `6a351574c88e316269214046ddcb7a1164db8351`.
It submitted the independently authored expected Program, rather than a
compiler-generated expectation. Rows were
`[{"x":7,"current_value":9,"original_value":7}]`; describe returned x,
current_value, original_value in that order, with the ordinary number and
nullable contracts. Same-request retry and Result rereading preserved the
Run and rows. This older-package control establishes common execution of
that expected IR only, not fresh-source Local/HTTP acceptance or CI success
for this branch.

At that historical baseline, complete public Local/HTTP acceptance and same-source PR CI were unfinished. FULL JOIN,
wider collection/frame combinations, NEAREST's installed Host connection and
the full language migration remain separate obligations. No full local Core,
packed suite, proof campaign or new native runtime build was requested here.
