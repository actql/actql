# Grouped implicit property names: authored names and retained values

Base: `origin/main` at `4fdcffb63f651e3dafa7dceaaf58a36a3e199cdb`.
This unit is independent of the grouped ORDER-subexpression PR. It changes
Frontend naming only; common value, grouping, analytic, sort, capacity and
publication owners remain authoritative.

## Counterexamples and adopted meaning

```sql
SELECT payload.score, COUNT(*) AS n
FROM objects GROUP BY payload.score ORDER BY score
```

The selected property key is already evaluated before GROUP. The old naming
call nevertheless looked for the original `payload` receiver in the closed
post-group fields and raised `UnknownColumn`. The independently authored
complete Program in `group_property_keys_test.mbt` checks with the ordinary
checker. The new regression compares that entire Program with bare, qualified
and backtick source spellings, without normalizing or patching product output.

The [adopted GoogleSQL implicit-alias rule](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#implicit_aliases)
derives a path's output name from its final identifier and a member access's
name from its member. Naming does not authorize accessing an ungrouped value.
The existing scoped SELECT already uses that rule.

A second counterexample uses the actual public Script lowerer:

```sql
SELECT l.id, l.payload.score, COUNT(*) AS n,
       ROW_NUMBER() OVER (ORDER BY l.id) AS rank
FROM objects AS l JOIN objects AS r ON l.id = r.id MAX_OUTPUT_ROWS 10
GROUP BY l.id, l.payload.score
QUALIFY score > 10 AND rank > 0 ORDER BY id
```

Flattening both JOIN input names during QUALIFY alias naming falsely raised
`AmbiguousColumn` for the qualified, unambiguous `l` receiver. The scoped value
lowerer must resolve it through its existing ranges, not the flat input helper.

## Repair

- Share the existing explicit/implicit authored-name rule in private
  `projection_output_name`; scoped SELECT and scoped/grouped QUALIFY use it.
- Preserve ordinary SELECT's existing missing/ambiguous receiver diagnostics.
  Its grouped naming call uses the pre-group naming snapshot, while actual
  value access still uses the closed grouping scope and evaluated key slots.
- Keep common property/type checks, SELECT sibling input meanings, qualified
  range resolution, duplicate-output rejection and hidden-slot removal.
  Naming never adds an input field to the grouped value scope.
- Do not expand an alias expression, restore an old range, add an executor or
  sort, weaken a ceiling, change a grammar/contract/pin, or rescue a missing
  current package asset with a historical client wire.

## Focused evidence

All paths below are relative to the reused, clean completed HAVING worktree
`worktrees/actql-frontend-having-grouped-subexpressions`. Historical receipts
and logs remain intact; the new branch starts directly from the stated main.

- Before repair: `run-rz2ahm`, `focused-test-P2KOBc`, **0/1**. The independent
  Program checks first, then source fails specifically with `UnknownColumn`.
- Initial narrow repair: `run-AS6RP5`, `focused-test-5lH08m`, **1/1** full
  Program comparison for all three path spellings.
- `run-AdYrU8` is **5/6**, not a pass. A test incorrectly demanded sorting
  the private key even though SELECT materializes public `SCORE` first. The
  corrected assertion follows that existing projection boundary; expected
  public values, names, order, types and NULL handling are unchanged.
- The actual public JOIN/QUALIFY red control is `run-z71Hst`,
  `focused-test-eBHy2R`, **0/1**, specifically `AmbiguousColumn`. The earlier
  standalone compile probe `run-mxkUI0` is a rejection with no public execution
  claim. Both failed probes remain distinct from the later repaired result.
- Final formatted implementation: `run-ntHzF9`. New grouped naming **6/6**
  (`focused-test-Ao1bZx`), ordinary property projection **6/6**
  (`focused-test-tvBfeo`), GROUP property keys **9/9**
  (`focused-test-rL8TKy`), QUALIFY **8/8** (`focused-test-LPHGq5`), JOIN
  implicit property aliases **3/3** (`focused-test-TEhPA7`).
- Readonly compilation-manifest freshness passes with unchanged grammar
  `sha256:582ecd6f94df7584160874befda4fa5f2a7d028f347599fc11e9685c10ba36e8`
  and barrier `sha256:8e3203948952a96d5153e9b0300431d29f5c209ce113f14c7f7149d3abac4818`.

## Public acceptance and remaining coverage

Ten normal cases and five preparation refusals are in the ordinary group-property
corpus. `--grouped-implicit-property-names-only` selects those same cases. They
include independent JSON, nullable receiver/field groups, duplicates, qualified
and quoted names, QUALIFY and JOIN/QUALIFY, CTE, explicit JOIN ceiling 10,
parameter predicate/LIMIT and empty typed results. Refusals retain their exact
public input code and zero Run admission/provider I/O.

The independent rows are NULL/count 2, score 10/count 1 and score 20/count 2.
QUALIFY's two expected rows have IDs 1 and 4, score 20/count 1 and ascending-ID
ROW_NUMBER values 1 and 4. Neither rows nor full ordered column contracts are
generated by the Frontend or an observed Result. Existing public checks retain
Named Result rows, Result.describe, complete stream, private-field absence and
owned request resend/attach/reread without reacquisition.

Fresh normal five-package Local/HTTPS execution is pending at this revision.
Source/checker acceptance alone is not runtime acceptance. Record the exact
clean producer revision and all five tarball digests; do not relabel an old
manifest. Exact submitted-SHA hosted CI, Wasm/native/full Core/full packed,
proofs/performance and broader Frontend completion remain unverified. No manual
CI rerun or merge.

## Shared public-verification capacity

At clean implementation `da8fef398d6cdf2c57f803ce32e8c4d70cf0f869`, the first
selected normal-pack attempt `run-zIMTXx` was refused at shared heavy-lock
acquisition. The guard reported D's `run-EJyXDs` in
`worktrees/actql-d-cancel-operation-identity`; no producer or consumer step
started. This is neither a product failure nor public acceptance. The other
owner's lock, checkout, processes and artifacts are untouched. Continue with
independent light integration/publication work; resume this same selected
acceptance when the common execution slot is available.
