# Correlated UNNEST visible star scope

This unit repairs an accepted query's missing output scope. It does not add an
UNNEST executor, alter ARRAY/NULL semantics, or assert expansion uniqueness.
Initial base: main `f40139bab9d0fe708cac97cbb1d8df4eec95d0d5`.

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

At this committed preparation snapshot, exact-HEAD normal five-package packed
Local/HTTPS acceptance is pending. Run the existing
`node scripts/test-packed-public-query.mjs --correlated-unnest-only` consumer
against the manifest/digest-verified clean source packages; it includes all
fourteen existing positives plus the thirteen new positives and ten refusals.
Do not exclude a failed fixture or read an old SHA's evidence as this HEAD's
success. The final public receipt and package digests belong in the PR report.

No full Core, Wasm/Native campaign, manual CI retry or merge is performed for
this unit. Draft CI and focused local success do not establish full integration
or completion of the overall Frontend goal.
