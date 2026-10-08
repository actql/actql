# JOIN to correlated UNNEST: preserve the actual typed prefix

Date: 2026-10-09. Frontend connection repair, not a new Graph/Relation contract
or a claim that the overall Frontend migration is complete.

## Baseline and counterexample

Main inspected: `b25708aa1913cd4735d9d1b5da5558cc2bb0202d`. This unit is stacked
on PR #1049, `2ab5b8e8d66af2895783621ab76acf120967e39d`, for its immutable
source-builder snapshot and common-typing prefix inspection. Its PR base stays
`fix/frontend-correlated-unnest-visible-star` until that dependency reaches main.
Neither PR is merged by B.

```aql
SELECT p.id, e.*, position
FROM parents p
JOIN keys k ON p.id = k.key MAX_OUTPUT_ROWS 4
CROSS JOIN UNNEST(p.items) e WITH OFFSET position
ORDER BY p.id, position
```

`parents.items` is a nullable ARRAY of nullable closed objects. Each object has
non-NULL numeric `code` and nullable string `label`. Parents 1 and 2 contain one
and three elements respectively; parent 2 includes a NULL object and duplicate
objects. Other parents have empty/NULL arrays. The independent ordinary Program
uses Values, the same JOIN condition/ceiling, derive, UNNEST, property access,
sort and select. Its common checker succeeds. Source compilation previously
returned `UnsupportedProjection` because the JOIN-to-Pipe call supplied neither
the actual input prefix nor its JOIN projection to child-star type inspection.

Retained red proof: `run-fPJfDO`, focused receipt `focused-test-UJgoi0`, **1/2**:
the independently authored Program passes, while authored source fails with the
exact projection refusal. This is compiler/checker evidence, not a claim of a
failed published Run.

## Repair and responsibility

- `query_join_chain.mbt::compile_join_chain_steps` forwards already-bound prefix
  nodes plus actual JOIN steps to the existing `compile_steps` type inspection.
- Script JOIN supplies its actual accumulated steps and Context. Stage-body JOIN
  supplies its emitted Values seeds and Context. Metadata inspection does not
  insert those nodes a second time into the Program.
- The existing expression, Relation and JOIN typing owners derive the ARRAY item
  contract from the real projected slots. This does not guess contracts from
  observed rows or from the parent's original schema after SET.
- Predicate, authored `max_output_rows`, parameter declarations, current and
  original-range slots, key/presence/nullability evidence, input ownership and
  physical execution strategy are unchanged. There is no new execution owner,
  compatibility fallback or fabricated ordering/key evidence.
- D's CTE/predicate/assert/Effect logic, C's Graph/snapshot and A's common runtime
  are not edited. The change remains the JOIN-specific call boundary.

The complete expected lowered Program is written independently in
`joined_unnest_star_test.mbt`; both SQL and Pipe are compared against it, including
JOIN predicate, ceiling, private projection, property, sort and public fields.
A separate ordinary JSON control uses readable bindings rather than compiler
names and is used for public execution comparison.

## Independent public obligations

`joined-unnest-star-source-input.mjs` adds nine successes and three preparation
refusals to the existing normal and selected correlated cohort. No new acceptance
harness, Program patching or Host profile is introduced.

- JSON control versus SQL/Pipe/DATA source, including quoted/parenthesized range.
- Independently expected rows: `(1,10,"a",0)`, `(2,20,NULL,0)`,
  `(2,NULL,NULL,1)`, `(2,20,NULL,2)`, with columns `id,code,label,position`.
  `code` is nullable because a NULL object projects typed NULL even though its
  field contract is nonnullable. Duplicate objects remain duplicate rows.
- Empty input retains the same complete Result columns/contracts.
- `SET items = [9]` changes the current array, while `p.items` retains the
  original. Whole-result star exposes only authored visible columns, including
  JOIN key and offset; private JOIN/array/property slots must not leak.
- Acquired JSON control and DATA source both read the installed Source once.
  Named Result rows and `describe().columns` must match independently. Attach,
  re-read and same-submission replay must retain the Run without further reads
  or admission, using the unchanged consumer's counter assertions.
- Non-array expression, removed range and zero JOIN ceiling must reject before
  Run admission/Source I/O. Public refusal is `ClientProgramInvalidInput`;
  focused core tests retain exact expression and syntax causes/positions.

## Limited verification and remaining coverage

- Focused JOIN/child-star/caller JS tests: **18/18**, `run-Kh8miC`,
  `focused-test-eRWcUv`.
- Selected fixture/correlated/public-profile Node tests: **18/18**,
  `run-nn4na2`, `focused-test-Alx11n`.
- Earlier **2/2** complete-Program comparison: `run-2WnHpg`.
- Intermediate test setup mistakes (ordinary JOIN without Pipe separator;
  expecting zero ceiling to reach lowering rather than syntax admission) were
  corrected without changing product semantics or public expected values. Their
  failed receipts remain distinct from the red product counterexample above.

Exact clean-HEAD five-package production and the existing
`test-packed-public-query.mjs --correlated-unnest-only` remain required before
public execution can be claimed. Record the resulting source SHA, package
digests, Local/HTTPS counts and retained receipt in the PR body. Success of
syntax/type checks alone is not that evidence.

This lightweight prefix does not manufacture absent imported Stage, Graph or
Model producer facts. Their source-specific paths still need actual common
schema bindings and separate acceptance where not already available. That is
remaining Frontend integration coverage, not a permanent language restriction.
Full Core, Wasm/Native, proofs, performance, full packed corpus and required CI
are not established by these focused local results.
