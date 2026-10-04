# SQL, Pipe and DATA semantic preservation audit

## Baseline and scope

Audited main: `ba3d6d12891f884b1bb55bb4d67bf043d4a58a94`.
The runtime was normally packed from that clean revision, using Node
22.23.2 and MoonBit 0.10.12+1634b282e. This record and its independent
fixtures do not change the runtime or claim a fix.

The audit reads the accepted scope rules in [query-text](../spec/query-text.md),
the [Pipe scope acceptance](2026-10-01-pipe-alias-scope.md),
[CTE composition acceptance](2026-10-01-cte-pipe.md),
[acquired DATA evidence](2026-10-03-acquired-data-branch-dispatch.md),
and [JOIN chain evidence](2026-10-03-join-chain-frontend.md).
Expectations are authored from these contracts; no expected Program or row
was generated from the product lowerer.

Assertion/terminal Effect syntax and the composition-specific Source predicate
and JOIN-limit representation belong to [#273](https://github.com/actql/actql/pull/273).
That work is not duplicated here. At the original audit checkpoint, the three
counterexamples below were handed off because they share `query_program/compile.mbt`.
The follow-up scope below separates the independent ORDER/Group branches from
D's assertion, Effect, Source predicate and JOIN-limit locations.

## Repair follow-up on current main

Repair baseline: `a4132d64f9cd83022d38bcb9c4e79d981fb2f803`.
Relevant Frontend source comparisons against the audited runtime were unchanged;
that inspection does not turn old execution evidence into a new-baseline run.

| Independent repair | Submitted HEAD | Executed evidence and remaining boundary |
|---|---|---|
| [Scoped ORDER binding reuse #286](https://github.com/actql/actql/pull/286) | `1c95aeda9c3c14c49062a1cf58af766346b0c609` | Follow-up focused JS 28/28. All four positives/one refusal pass on both packed Local and HTTPS from clean runtime `06256fe791f85e7dbe4f6c71ea69bb0054e6b0fb`; adjacent RESULT removes the redundant cleanup projection. Historical DISTINCT refusal remains separately recorded. |
| [Aggregate input scope #287](https://github.com/actql/actql/pull/287) | `d1d98c5414872bca35a6f3ec5182c211f269f81e` | Focused Group/JOIN/parser JS 28/28, then Group/Pipe including SUM 11/11; independent SQL/Pipe Program comparison Node 1/1. SET/DROP SUM and two refusals pass on both packed transports. Ordered original/current-key controls remain `Execution(Physical(ExecutionLimit))`. |

Each repair records its clean runtime source and normal tarball digests;
subsequent submitted commits add evidence and tests without changing that
verified runtime source. See each repair record for the exact source-to-artifact
relationship.
The narrow ORDER positive corpus is successful; the Group corpus remains
incomplete and #287 stays Draft. Automatic
[ORDER CI 37162504341](https://github.com/actql/actql/actions/runs/37162504341)
completed successfully for submitted `1c95aeda9c3c14c49062a1cf58af766346b0c609`,
including final `pipeline-evidence` and `check`. Its ordinary client-packed
artifact `11287879354` was built from clean merge tree
`7c3fbc8742a2efc1ff89ba4a7d21300ba70bb059`. The unchanged rebound alias,
DISTINCT alias, unchanged-expression and qualified-input cases each pass on
Local and HTTPS. The acceptance helper also executes the displaced-range
refusal with typed input rejection, unchanged Run/I/O counters and request
lookup `not_found`; refusals do not print per-case success lines. The exact
CI source and digests remain separate from the local packed revision.

CI artifact SHA-256 (`-0.0.0-development.tgz`):

| Package | SHA-256 |
|---|---|
| actql-client-wire | `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0` |
| actql-sdk | `2fc910067348e421346945ced1e728e107bbe6fa455ee00f9d71da46e8123c5b` |
| actql-run-host-core | `47f57353549cc0ac1b51e57d346e49ad8f2526fa9366e15c01752c567cea869f` |
| actql-local-node | `ad03e5a534461469b6daf65ab4b7f2008694f7e273e895524abf587d940f5078` |
| actql-node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

[Group CI 37162983732](https://github.com/actql/actql/actions/runs/37162983732)
passes client-distribution with independent complete SQL/Pipe Programs;
client-packed and its Client aggregate fail, while other jobs remain running.
The first packed failure is still `group-snapshot-original-key` on merge tree
`6011bb1fcc48305e7351ea8dbf3cf86df542f8bc`; later Group cases and HTTP are
not reached. No previous failed HEAD is relabeled as a success. The local
independent-Program comparison passed 1/1 separately from that CI distribution
result. No Host ceilings, providers, physical strategies or common owners
were changed. The CTE shared-acquisition predicate defect remains D's handoff.

The [capacity handoff](2026-10-04-frontend-capacity-handoff.md) preserves all
three original refusals, actual checked Programs and independent expected rows.
A owns the common derivation/reservation investigation; B will finish #287's
remaining public corpus after A's fixed SHA. D can reuse the common-boundary
handoff without duplicating those cases. The handoff now accounts for the
observed Group totals using child holding, child execution and parent copy
holding, rather than inferring a fragment peak by subtracting base scratch.
B's adjacent RESULT repair independently closes the ORDER
example without changing the capacity formula or 512 MiB ceiling. Group's two
capacity refusals remain unresolved. No estimate defect is inferred solely from
zero current reservation or a small physical fixture.

NEAREST standard Host connection is separately A-owned; the existing
[fixture directory](../../spec/frontend/fixtures/nearest-keep/README.md) and
[prepared consumer](../../scripts/fixtures/nearest-public-input.mjs) remain
unchanged. The [connection handoff](2026-10-03-nearest-public-connection-boundary.md)
now records that assignment and keeps historical preparation evidence separate.

## Reproduced defect: scoped Pipe ORDER reuses the wrong value

```aql
FROM records |> AS original |> SELECT -id AS id
  |> ORDER BY -id |> RESULT answer
```

Input: `[{"id":1,"amount":10},{"id":2,"amount":20}]`.
SELECT produces `id=-1,-2`; ORDER references that output name and computes
keys `1,2`. Expected rows are `[{"id":-1},{"id":-2}]`.
Packed Local and HTTP both instead publish `[{"id":-2},{"id":-1}]` with
status `succeeded`.

`compile_steps`' scoped ORDER branch (baseline lines 2330–2336) compares raw
SELECT/ORDER expression spelling through `same_expression`. The references
inside those expressions have different meanings after alias replacement.
It reuses the SELECT's negate slot instead of computing ORDER's negate of the
evaluated output slot. The normal SQL path's `reusable_order_expression`
already checks reference meaning. Its existing SQL/JOIN regression and this
audit's ordinary SQL control preserve the expected order.

Required repair: compare resolved reference meanings before selected-slot
reuse, retaining the scoped input and output bindings. Evaluate the SELECT
once and the genuinely different ORDER expression once. Do not restore an
old range alias or expose a hidden sort column.

## Reproduced defect: a CTE predicate filters another JOIN input

```sql
WITH chosen AS (SELECT id FROM records WHERE id = 1),
     pairs AS (
       SELECT r.id AS id FROM chosen AS l CROSS JOIN records AS r
     )
SELECT id FROM pairs ORDER BY id
```

With the same two input rows, `chosen` has one row and the independent right
operand `records` still has two. Expected rows are `[{"id":1},{"id":2}]`.
Packed Local and HTTP both publish only `[{"id":1}]`, again as `succeeded`.

`compile_cte_query`'s `referenced_elsewhere` check (baseline lines 2935–2949)
looks at the principal FROM relation of each term, missing `records` on a
JOIN right operand. It hoists `chosen`'s WHERE into shared acquisition, removes
the consumer WHERE, and rebinds the original Source to that filtered capture.
The next CTE then correctly reads the wrong, incomplete retained input.

Required repair: account for actual Source dependencies on every JOIN operand
and supported composed term, under the existing lexical CTE scope. When
another consumer needs the original Source, retain the complete acquisition
and leave this WHERE on `chosen`. Do not acquire the original Source a second
time, remove the predicate, or equate a shadowing CTE name with an outer Source.

Read-only follow-up at D's submitted
`8a5195451195b7e4566b19bf7ba9fb5772b8f2d1` confirms that
`compile_cte_query` still compares only each term's principal relation in
`referenced_elsewhere` (lines 2964–2980), omitting JOIN-right dependencies.
D's improved DATA/script dependency scan does not replace this direct CTE
path: `source_frontend/lower.mbt` sends text scripts with no DATA declarations,
and SQL input, to `query_program.compile`. This is current-source evidence,
not another execution of the latest D runtime. The wrong-row execution above
remains bound to the historical audited main. D's #273 composition acceptance
does not cover this zero-DATA CTE counterexample. The authored source, expected
two rows, one acquisition and no reacquisition are unchanged; no parallel
Source-predicate repair was made in B's branch.

## Reproduced defect: aggregate input loses an immutable range snapshot

```aql
FROM records AS before |> SET id = amount
  |> AGGREGATE SUM(before.id) AS total |> RESULT answer

FROM records AS before |> DROP id
  |> AGGREGATE SUM(before.id) AS total |> RESULT answer
```

With `id=[1,2]` and `amount=[10,20]`, both should return `total=3`.
SET and DROP retain `before.id` as the original input value. AGGREGATE closes
that range in its **output**, after resolving its input expressions. The
current-column control `SUM(id)` after SET correctly returns `total=30`.
These rules follow the adopted Pipe scope contract and the pinned
[GoogleSQL SET and AS descriptions](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/pipe-syntax.md).

The scoped Group branch in `compile_steps` (baseline lines 1736–1757)
materializes only the current visible columns and clears `pipe_ranges` before
resolving group keys and aggregate arguments. The later resolver therefore
returns `UnknownColumn` for `before.id`; DROP also discards its needed physical
slot. Keep the input scope and required original slots through aggregate
argument/key lowering, then close the output scope. Do not revive the old
range after aggregation or replace its references with the current column.

The [three authored aggregation cases](../../spec/frontend/fixtures/semantic-audit/group-cases.json)
were executed using the same verified external installation and tarball
digests from the audited main; no runtime rebuild or repack was needed.
Both old-range cases fail on both Local and HTTP with `ClientProgramRejected`,
with **zero durable Run admissions and zero Source acquisition sessions**.
The current-column control succeeds on both, returning `[{"total":30}]`,
ordered column `total:number nullable`, a complete row stream, one acquisition,
and no further acquisition on same-request retry or attach/read.

Focused JS compilation: 3 tests, 1 control passed and 2 pre-fix regressions
failed with `UnknownColumn`. The control's common checker requests existing
numeric input evidence; that isolated fixture is not counted as a closed
Host execution. The packed control establishes the real execution separately.
Packed observations: 6 cases across both transports. Recomparison against the
independently corrected SUM contract gives 2 controls passed and 4 pre-fix
regressions failed. SUM's nullable output follows its empty-input contract
(`relation_typing/aggregates.mbt`); the initial private harness incorrectly
expected non-nullability. That harness error is retained in the raw evidence
and is not classified as a product defect. Recomparison used saved
observations and did not rerun the Host or change any expected row.

This third issue initially shared the file-level edit boundary. The follow-up
Group repair above edits only its independently owned aggregate scope branch.

## Focused evidence

The [four authored public cases](../../spec/frontend/fixtures/semantic-audit/cases.json)
retain input rows, source text, expected rows and ordered full column contracts.

| Public case | Embedded Local | HTTP |
| --- | --- | --- |
| Pipe rebound ORDER | Wrong row order reproduced | Same wrong order |
| CTE JOIN shared Source | Missing second row reproduced | Same missing row |
| Ordinary SQL rebound ORDER control | Passed | Passed |
| DATA WHERE + parameter + ORDER + LIMIT/OFFSET, NULL and duplicate input | Passed | Passed |

For all eight executions, Named Result description columns match the authored
contracts; rows reach reader state `complete`; exactly one Source acquisition
session occurs; exact resubmission and attach/read add zero sessions. These
facts do not make the four wrong-row comparisons successful. The final
focused packed comparison is **4 passed / 4 failed**, reflecting two defects
on both transports. The compiler-only pre-fix regression separately has
**1 passed / 2 failed**; its failing cases inspect distinct ORDER expression
references and the retained capture predicate, not public execution.

SQLite 3.53.1 independently corroborates the expected rows using an explicit
projected subquery for Pipe output scope and the unchanged SQL CTE query.
This is independent arithmetic/relational corroboration, not GoogleSQL backend
conformance. No alternate evaluator was added to the Frontend.

Initial audit harness mistakes (an unclosed block, treating `Reader.state`
as a property, and reusing a database's table-creation setup) were corrected.
Their failed invocations remain diagnostic evidence and are not product
defects or passing acceptance. The already verified tarballs were reused;
the runtime was not repacked for those harness corrections.

| Normally packed artifact | SHA-256 |
| --- | --- |
| client-wire | `5da98d3edb615f960f0511be9d6e61431cd34d02304a8bd6b6e576f7775f91a0` |
| sdk | `2fc910067348e421346945ced1e728e107bbe6fa455ee00f9d71da46e8123c5b` |
| run-host-core | `302637e181b1dbb3c053ed2b109355230e98fb5652a4242666840dcdd0b7af30` |
| local-node | `a87efa0d9fa9621842f9c13fae74db2cad1f9c8f5b58a15a290045e6bde81c5c` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

## Discriminating NULL and JOIN multiplicity controls

[Two authored CTE JOIN cases](../../spec/frontend/fixtures/semantic-audit/join-null-cases.json)
contrast LEFT and INNER with the same input: `id=[1,2,3]`,
`amount=[NULL,20,20]`. A second CTE keeps only `id=2`; the JOIN condition is
`l.amount = r.amount`, not `true`. LEFT must retain the NULL-extended first
row and two identical projected matches; INNER must retain the two matches
without that first row. Ordering is by the qualified, non-output `l.id`.

All 4 Local/HTTP comparisons pass on the same unchanged external main runtime.
They confirm the authored rows (including duplicates), ordered columns
`amount,matched`, their nullable contracts, complete streams, exactly one
shared Source acquisition and no additional acquisition on retry/attach/read.
These controls distinguish a lost ON condition, changed JOIN kind, NULL-equals-
NULL treatment, duplicate elimination and qualified-input sorting. They do not
establish every JOIN or NULL combination or change the three outstanding
regressions into passes.

## Read-only checks and remaining coverage

Inspected ordinary/CTE/set/JOIN LIMIT and OFFSET lowering retains `take.count`
and `take.offset`; parameter declarations are retained by `program_root` and
parameter references remain typed expression nodes. The inspected pre-JOIN
WHERE paths retain the authored filter. No additional silent replacement was
identified in these paths; the four-case execution sample is not exhaustive.

Broader NULL/JOIN combinations, remaining aggregate input scopes, all parameter types,
failure/cancellation campaigns and frontend-wide conformance remain unaudited.
Explicitly rejected profile gaps such as LIMIT 0 are not reclassified as silent
lowering errors or fixed by this record. No full Core, proof, performance or
packed campaign, manual CI rerun, merge, or deployment was performed.
At the original audit checkpoint, all three defects were unfixed. The repair
follow-up above supersedes that delivery status, without reclassifying these
historical failures as passes. This audit record itself changes no runtime.
