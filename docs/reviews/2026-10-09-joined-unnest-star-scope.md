# JOIN to correlated UNNEST: preserve the actual typed prefix

Date: 2026-10-09. Frontend connection repair, not a new Graph/Relation contract
or a claim that the overall Frontend migration is complete.

## Baseline and counterexample

Main inspected: `b25708aa1913cd4735d9d1b5da5558cc2bb0202d`. This unit is stacked
on PR #1049, `2ab5b8e8d66af2895783621ab76acf120967e39d`, for its immutable
source-builder snapshot and common-typing prefix inspection. PR #1049 subsequently reached main through
`4aa66a85ebd90f037b9a5a4af3d0850ed91b1bd1`, normally merged into this unit.
The new PR targets main and has no unmerged parent dependency. B performs no PR merge.

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

The first exact-HEAD packed attempt exposed two further Frontend connections in
the authored quoted/parenthesized case. The existing grammar already specifies
`source_alias = [ "AS" ], identifier`, including quoted identifiers. The
optional-source-alias parser now consumes quoted names as well as ordinary
non-clause words. Unquoted clause starters retain their original behavior.

For scoped Pipe expressions, a parenthesized receiver naming a range without
also naming a visible value binds the existing range column. The existing
`expression_with_field_bindings` owner preserves source locations and removes
only the syntactic qualification subtree. If the receiver names an object
column, it remains ordinary property access; it is not flattened into a range
column. Private binding names cannot capture authored references. Inspection,
receiver traversal, collision checks and AST remapping consume the existing
expression work allowance. Unknown/dropped ranges remain exact refusals.
No temporary row object or evaluator is constructed.

The complete expected lowered Program is written independently in
`joined_unnest_star_test.mbt`; both SQL and Pipe are compared against it, including
JOIN predicate, ceiling, private projection, property, sort and public fields.
A separate ordinary JSON control uses readable bindings rather than compiler
names and is used for public execution comparison.

## Independent public obligations

`joined-unnest-star-source-input.mjs` adds eleven successes and three preparation
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
- An object-column/range collision contrasts a row `score=90` with the nested
  object `score=10`. Independent JSON control and text both expect 10. This
  prevents fixing range qualification by changing value-receiver semantics.

## Limited verification and remaining coverage

- Focused JOIN/child-star/caller JS tests: **18/18**, `run-Kh8miC`,
  `focused-test-eRWcUv`.
- Selected fixture/correlated/public-profile Node tests: **18/18**,
  `run-nn4na2`, `focused-test-Alx11n`.
- Earlier **2/2** complete-Program comparison: `run-2WnHpg`.
- After quoted-range repair: **35/35 JS**, `run-pfVVM5`,
  `focused-test-7vu68i`; **18/18 Node**, `run-zPUe3q`,
  `focused-test-ncaKwA`. These include ordinary nullable/computed property and
  ORDER reuse consumers, private-looking name collisions and exact scope errors.
- Intermediate test setup mistakes (ordinary JOIN without Pipe separator;
  expecting zero ceiling to reach lowering rather than syntax admission) were
  corrected without changing product semantics or public expected values. Their
  failed receipts remain distinct from the red product counterexample above.

The first normal five-package campaign at
`c53b51c8a46b741160d4c97ec0ebaeb99e0dbb08` (`run-to2xeR`,
`public-query-evidence-2aMkwD`) passed 30 Local successes, including new JSON
control/SQL/Pipe, then rejected quoted/parenthesized source. Later cases,
refusals and HTTPS were not reached. The failed receipt and Store are retained.
Parser diagnosis (`run-E3LeIK`) fixes the exact `Syntax("Expected end of one
query")` location, byte 42; after quoted alias admission, `run-ta44Ky` isolates
the unresolved parenthesized receiver. After binding the existing range column,
that focused case succeeds (`run-6IkOQP`). An intermediate missing closure
error-type declaration is a compilation/setup failure, not runtime evidence.

Normal five-package production and the existing
`test-packed-public-query.mjs --correlated-unnest-only` completed successfully at
clean source `7cd912cd451701b4ed1e912c735a033905e799cb`. Receipt
`public-query-evidence-31GLNF` records all ten commands with complete output and
exit/verification status zero, overall passed/complete and success artifacts
removed. Local and real HTTPS each finish 38 positive cases and 13 refusals.
Five exact-code refusals per transport are logged individually; the other eight
are established by the reviewed refusal loop and completed consumer, not by
inventing additional log lines. The new unit contributes eleven successes and
three exact `ClientProgramInvalidInput` refusals. Rows, complete columns/types,
NULL propagation, multiplicity, private-field exclusion and replay/acquisition
counter assertions use the unchanged public consumer.

The outer local wrapper `run-d0wMSI` reports exit 1 because its stdout/stderr
forwarding encountered EPIPE after all three child steps passed. Its retained
output is complete, but caller forwarding is incomplete. Do not report this
wrapper as passed or treat it as a product failure; the inner public receipt
and child command results establish the acceptance evidence. No rerun solely to
repair the terminal stream is performed.

The main integration changes only unrelated reporting tests and the parent's
review record. Compiled source, frontend corpus and public consumer remain
identical to the clean packed source. Retained manifest and independent digest
verification identify all five tarballs; submission evidence must distinguish
that source SHA from the later integration/documentation HEAD. Required CI and
full target coverage remain unverified.

This lightweight prefix does not manufacture absent imported Stage, Graph or
Model producer facts. Their source-specific paths still need actual common
schema bindings and separate acceptance where not already available. That is
remaining Frontend integration coverage, not a permanent language restriction.
Full Core, Wasm/Native, proofs, performance, full packed corpus and required CI
are not established by these focused local results.

After the ordinary main merge, the selected fixture/profile Node gate passes
18/18 (`run-6rR2d0`, `focused-test-XcSyIY`). The retained package/log rehash and
source-correspondence audit is `/private/tmp/actql-b-joined-unnest-star-20261009-acceptance-audit.json`.
