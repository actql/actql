# Correlated UNNEST visible star scope

This unit repairs an accepted query's missing output scope. It does not add an
UNNEST executor, alter ARRAY/NULL semantics, or assert expansion uniqueness.
Initial base: main `f40139bab9d0fe708cac97cbb1d8df4eec95d0d5`.
The ordinary integration merge adopts main
`b25708aa1913cd4735d9d1b5da5558cc2bb0202d`, including #1047's repaired
DISTINCT ARRAY reference handling and the current shared mutation checks.

## Independent counterexample

```sql
SELECT * FROM parents p
CROSS JOIN UNNEST(p.items) element WITH OFFSET position
ORDER BY p.id, position
```

For `(id, items)` rows `(2, [2,NULL,2])`, `(1, [1])`, `(3, [])`, `(4, NULL)`,
the declared output columns are `id, items, element, position`. The expected
rows are the four expanded rows, ordered by parent id and zero-based offset;
both copies of 2 and the NULL element remain. Empty and NULL arrays contribute
no rows. These obligations follow the adopted
[GoogleSQL UNNEST profile](../../spec/query-text.md#declared-unnest-value-tables),
not row sampling or implementation-generated expectations.

The complete independently authored Values Program passes the ordinary checker.
The original text fails lowering with `UnsupportedProjection`:
`run-HiJxuO`, `focused-test-EISosl`, 1/2 passed. This is a compiler-boundary
reproduction, not evidence of an incorrectly published Run.

The source-free element probe has no preceding Relation schema. It therefore
cannot type `p.items`, and the star guard refuses the query despite an already
typed, lowerable array. Explicit parent projections do not establish the child
schema and are not a workaround for the missing star semantics.

## Repair and common boundary

The lowerer first resolves the ARRAY expression using its existing current
column/range scope and emits the ordinary private `derive`. If a correlated
star needs a still-unknown child contract, it inspects that actual lowered
prefix through existing `MemberResolution`, Values, Relation and expression
typing. It then uses the common ARRAY item contract to expand the visible
columns. Final ordinary Program checking remains mandatory.

The prefix includes actual SET/SELECT/UNNEST operations and private range
snapshots. An initial source schema cannot replace its final schema: after
`SET items = [@replacement]`, unqualified `items` is the new array while
`p.items` retains the original array. Dropped ranges are still refused.

`program_source_builder.snapshot` admits an immutable, bounded source fragment
without closing the construction session. It shares `finish`'s existing tree
admission, usage and origin logic. `finish` still closes before admission;
failed/closed builders remain closed and foreign nodes remain rejected. The
generated interface is produced with pinned `moon info`, not hand-edited.
This API grants no Program, Source, key, order, capacity or execution evidence.

The lowerer uses only type facts for expansion; common checking continues to
own nullable receiver propagation, presence, duplicate names, ARRAY bounds and
key transfer. No parent key is asserted unique after one-to-many expansion.
No field, sort slot or range snapshot is added to the public Result by the
prefix inspection itself. Literal/parameter-only probes retain their existing
path. Inspection and construction keep their declared work/tree limits.

Standalone Values/schema-backed compilation and the ordinary DATA Relation
path pass their actual prefixes. The script change adds only call metadata;
it does not change D's CTE, predicate, assert or Effect lowering. Imported
Stage/Graph/Model producer facts that this lightweight prefix cannot establish
remain unproven; this unit does not invent schemas for those callers or claim
every correlated JOIN/CTE/Graph shape complete.

## Independent acceptance and focused evidence

`correlated_unnest_visible_star_test.mbt` compares complete SQL/Pipe Programs
with hand-authored ordinary Values/derive/UNNEST/property/sort/select Programs.
It separately checks SET's changed object array versus the original scalar
array, non-array input, dropped range and work-limit refusal with exact causes.

`correlated-unnest-star-source-input.mjs` adds thirteen positives and two exact
preparation refusals to the existing correlated cohort and normal corpus.
The two independent JSON controls and authored text cover scalar `*`, nullable
closed-object `e.*`, SQL/Pipe, quoted/parenthesized receivers, duplicates,
NULL fields/receivers, empty parents/arrays, original/current SET scopes, DATA,
and an unchanged filter/order/LIMIT obligation. Expected object `code` is
nullable even though its declared member is non-NULL, because its receiver may
be NULL. These are the existing canonical closed-object contracts, not new
ordered GoogleSQL STRUCT construction semantics.

The existing public consumer compares Named Result rows and `describe().columns`
including order and full contracts. It checks no hidden fields, acquisition
counters, attach/read/resubmission identity, and exact rejection codes with
no Run admission or Source I/O. No generated Program is patched by a test.

Focused local checks before integration:

- `node scripts/local-checks.mjs test moon --timeout-seconds 900 -- --target js`
  selecting the new scope tests, existing correlated/STRUCT/checked-array
  callers and builder/snapshot tests: **28/28**, `run-w82q9O`,
  `focused-test-Px4Szj`.
- The selected new scope file alone after repairing its test initializer:
  **4/4**, `run-W4fLBC`, `focused-test-ybtdYD`. Earlier `run-MK6PRj` used an
  unsupported STRUCT constructor in the test setup; `run-HSFKjr` had an unbound
  test variable. Neither is counted as a product failure or a successful check.
- Selected Node star/correlated corpus and public-profile tests: **15/15**,
  `run-mcQSoO`, `focused-test-NdUFd8`.
- After the ordinary main merge, the new scope tests and directly merged
  DISTINCT ARRAY reference caller tests: **9/9**, `run-v1fsVL`,
  `focused-test-UEOS1H`.

At committed source `2ab5b8e8d66af2895783621ab76acf120967e39d`, normal
five-package production and the existing
`node scripts/test-packed-public-query.mjs --correlated-unnest-only` consumer
passed. Receipt `public-query-evidence-SnBUYf` records ten complete successful
commands from that clean SHA. Each Local/HTTPS entrance covers 27 positives and
ten refusals, including all existing correlated cases and the thirteen new
positives. The final receipt and five package digests are retained separately
from the earlier failed campaign below; no fixture was excluded to pass.

No full Core, Wasm/Native campaign, manual CI retry or merge is performed for
this unit. Draft CI and focused local success do not establish full integration
or completion of the overall Frontend goal.

## Public caller failure and local repair

Normal five-package production and digest verification at
`c6a2a0ca0a15fb25ea62f2fe4064f0dd0efae4cd` succeeded. The existing selected
consumer stopped at `correlated-unnest-joined-parent`, after thirteen existing
Embedded Local positive cases. The new star cases, refusals and HTTPS cohort
were not reached. Evidence: `run-4TLXJX`,
`worktrees/.codex-scratch/public-query-evidence-f1SvOG`; command `010` has
complete stdout/stderr and exit 1. No acceptance success is inferred from this
partial run; its Store, tarballs and digest manifest remain protected.

The unchanged source joins `records r` to `(SELECT 1 AS key) k` with
`MAX_OUTPUT_ROWS 4`, expands declared `@items = [2,NULL,2]`, and orders by
`r.id, position`. Its public refusal was `ClientProgramInvalidInput` before
Run admission. A focused reproduction through the same script input-binding
path identifies `ExpressionTyping(UnknownParameter("items"))`:
`run-5ClKgQ`, `focused-test-30t5dr`, 5/6 passed. The direct standalone CTE
probe instead returned `UnsupportedCte` (`run-tnLd1B`); it is a different
route and is not used as the public failure's cause. Diagnostic test setup
errors are retained separately and are not successful checks.

`compile_join_chain_steps` omitted `context.parameter_declarations` when
calling `compile_steps`. Its source-free ARRAY probe therefore lacked a
declaration even though the Program root and parameter name resolver had it.
The repair forwards existing declarations from the stage/script callers
through the common joined-row lowerer. It changes neither the predicate nor
the declared JOIN bound, CTE capture, stage ownership or execution strategy.
The parameter and all original fixture rows/contracts/order remain unchanged.

After this local forwarding repair, the scope/caller regressions and existing
JOIN-chain tests pass **14/14**, `run-WTr3LV`, `focused-test-h6UKP8`.
That receipt records a dirty preparation worktree based on `c6a2a0ca0`; it is
not a clean-HEAD unit-test result. The subsequently committed `2ab5b8e8` has
the independent normal packed success above. Failed `c6a2a0ca0` packages do
not establish the later repair's success.

## Root integration review

Root independently rehashed all five retained `2ab5b8e8` tarballs against their
unaltered clean-source manifest and final public receipt, and verified all ten
command results and captured-output hashes. Final Local/HTTPS positive logs
and the new named refusal logs agree with the independent selected fixtures.
The final ordinary core/adapter admission remains mandatory; prefix inspection
supplies only type facts and cannot grant Source access or fabricate key proof.

Root fixture/profile tests pass **15/15**, `run-r44pED`. The later normal
integration of main preserves the complete `2ab5b8e8` source tree, module and
frontend fixture/consumer files; it adds #1050's unrelated reporting tests and
this documentation correction. The final integration review uses source and
artifact correspondence, not a repeated packed campaign for a new SHA.
There is no claim of new-SHA packed, Native/Wasm or hosted CI success.
