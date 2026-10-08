# Grouped property receivers retain their source scope

This is a Frontend repair against main `a39a95b6b70b1e8c996d7b884586ef0eaffac10e`.
It does not change expression, grouping, type, identity, ordering, capacity or
Host contracts. It does not depend on the signed DISTINCT-order branch.

## Counterexample and adopted meaning

The existing expression lowerer resolves `(payload).score` by looking up the
input object column `payload`, then applying its property. With an existing
range alias `payload`, `payload.score` can instead resolve the range's separate
input column `score`. These values are deliberately different in the fixtures.
Appending an explicit property name to its receiver before source resolution
loses that distinction.

```sql
SELECT (payload).score AS object_score, COUNT(*) AS n
FROM objects AS payload
GROUP BY payload.score
```

The object receiver is not grouped. This source must refuse with the existing
`Expression(UnknownReference)` lowering diagnostic. The previous grouped-key
comparison flattened both paths and could substitute the range column's key.
The converse reference and a computed subtree have the same obligation.

```sql
SELECT payload.score AS input_score, (payload).score AS object_score,
       COUNT(*) AS n
FROM objects AS payload
GROUP BY ALL
ORDER BY input_score, object_score
```

Both values must be grouping keys. The existing inference also flattened both
receivers, treated them as one key and discarded the object property. The
selected [GoogleSQL GROUP BY ALL rule](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#group_by_all)
infers from the resolved input paths, and only a path of the same input value
can cover another. This repair preserves the adopted implementation profile;
it does not establish general ordered STRUCT grouping or GoogleSQL compatibility.

## Repair

- Keep the Reference receiver path and explicit Property suffix separate.
- Resolve the original receiver first, then compare its physical input slot and
  ordered member suffix. Unknown receivers never prove equality.
- Use that comparison at every subtree when reusing GROUP keys. Keep exact
  operators, typed parameters, conditional demand and existing work guards.
- Apply the same boundary to GROUP BY ALL prefix inference, SELECT-key reuse,
  hidden HAVING aggregate inputs, HAVING predicates and grouped ORDER.
- Use the existing common expression/group owners and private-slot projection.
  No row sampling, new evaluator, fabricated existence/uniqueness, acquisition,
  compatibility path or relaxed admission is added.

## Independent obligations

The MoonBit test contains a complete hand-authored Values/derive/group/select
Program with both input slots; ordinary checking must admit it. It checks
explicit GROUP and GROUP BY ALL against that Program, including quoted members.
Computed key subtrees and HAVING/ORDER refusal contrasts retain the same scopes.

The public JSON control is independently authored and runs through capture,
CASE/property projection, group, sort and Named Result. Its input has a repeated
row and distinct object scores under the same range-column score. The expected
rows, declared column order and nullable contracts are authored directly:

```json
[
  {"input_score":10,"object_score":20,"n":2},
  {"input_score":10,"object_score":30,"n":1},
  {"input_score":20,"object_score":null,"n":1}
]
```

Seven new positive cases and five typed refusals are registered in both the
normal public corpus and its existing GROUP BY ALL selection. They cover the
independent JSON control, both key forms, quotation, computed subtrees, HAVING,
empty typed output and ungrouped object/range references. The existing harness
checks Result.describe contracts and column order, rows/order/multiplicity,
private-slot exclusion, acquisition count, resend/reread without reacquisition,
and zero admission/provider I/O for preparation refusals. No lowering output is
patched in the acceptance harness. Existing GROUP BY ALL cases remain present.

## Verification record

- Red: `run-JjN4e1` / `focused-test-e7W65s`, two selected tests failed before
  the product repair. The scope refusal and retained object-key assertions both
  detected the flattened receiver.
- First repair compilation failed on an incorrect use of `Array.to_array`:
  `run-S623Rj` / `focused-test-JEnRzo`. This is not runtime evidence.
- Focused JS after repair: 37/37 in `run-V6pnCL` / `focused-test-0Qas1t`.
- Final expanded focused JS: **51/51**, `run-qd93eT` /
  `focused-test-0UxI0p`, including property grouping, GROUP BY ALL, SELECT,
  HAVING and ORDER subtrees, implicit property outputs and membership atoms.
- The first Node attempt found a syntax error in the new authored fixture:
  `run-bmBZCJ` / `focused-test-3Ju1pF`; it was corrected.
- Final focused Node: **14/14**, `run-1xLNIL` /
  `focused-test-8R8DRz`, covering independent receiver obligations, normal and
  selected registration and existing public profiles.
- Changed MoonBit files were formatted with the pinned formatter; whitespace
  checks passed. The focused source tree is committed unchanged apart from
  formatting and this evidence record.

Commands:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 900 -- --target js \
  src/query_program/group_property_receiver_scope_test.mbt \
  src/query_program/group_property_keys_test.mbt \
  src/query_program/sql_group_by_all_test.mbt \
  src/query_program/having_grouped_subexpression_test.mbt \
  src/query_program/order_grouped_subexpression_test.mbt \
  src/query_program/grouped_implicit_property_name_test.mbt \
  src/query_program/grouped_in_atoms_test.mbt \
  src/query_program/sql_grouped_subexpression_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 300 -- \
  scripts/group-property-receiver-source-input.test.mjs \
  scripts/group-by-all-source-input.test.mjs \
  scripts/public-query-profiles.test.mjs
```

At this committed snapshot, exact-HEAD five-package Local/HTTPS acceptance is
pending. Its subsequent manifest, digests, commands and results belong in the
PR body without reattributing earlier evidence. CI, other targets, full Core,
other public cohorts and broader Frontend gaps are unverified by this unit.
