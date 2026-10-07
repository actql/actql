# Declared STRUCT UNNEST field expansion

Adopted main: `3a01ebcea5af032bb22cfe5b55132d0e36ad4b77`.
This independent Frontend unit does not depend on the unmerged Pipe JOIN range
PR #759 and changes no common Owner, Program wire contract or grammar pin.

## Counterexample and existing common support

```sql
SELECT * FROM UNNEST(@items) element WITH OFFSET position ORDER BY position
```

`items` is a bounded nullable array of nullable closed objects with `id`
(nonnullable number) and `label` (nullable string). Independent input
`[{id:2,label:null},null,{id:2,label:null}]` must produce:

```json
[{"id":2,"label":null,"position":0},
 {"id":null,"label":null,"position":1},
 {"id":2,"label":null,"position":2}]
```

The independent complete JSON Program uses ordinary `derive`, `unnest`,
nullable `property`, `sort` and `select`. It passes the common checker for
nonempty, empty and NULL arrays. Before the repair, the matching source fails
0/1 at `focused-test-uOdjZ0` / `run-5OHgqt` because the Frontend permits only
scalar stars. A preceding attempt failed to compile the test helper's wrongly
named Program type; it is not a product failure.

The selected [GoogleSQL reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/query-syntax#unnest_operator)
expands STRUCT fields, retains the whole value through the range variable and
keeps OFFSET separate. `element.*` therefore excludes OFFSET; `*` includes it.
NULL elements propagate through the common property evaluator. Nested object
fields remain object columns rather than recursively flattening. Columns are
resolved from declarations even on empty input, never from sampled values.

## Minimal repair

The UNNEST lowering branch derives declared object fields into private slots,
then uses the existing scoped projection. Visible columns and the original
whole-object receiver are separate Frontend metadata. SET/DROP/RENAME preserve
the original range's slots; AS and SELECT replace its scope. The existing
SELECT-owned ORDER boundary temporarily retains the input meaning, including
its original object receiver. Qualified field references reuse their evaluated
property slots; alias-priority and selected-expression reuse keep their existing
meaning checks. No private field is exported by star.

Unknown array-expression contracts remain explicitly unsupported for star.
This does not add general ARRAY constructors, correlated UNNEST, implicit
aliases or generic object expression stars. Existing scalar input behavior and
parameter validation remain unchanged. No CTE acquisition, assertion, Effect,
JOIN-ceiling, execution, capacity, persistence or shared checker code changed.

## Focused verification and remaining execution evidence

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/unnest_struct_star_test.mbt \
  src/query_program/unnest_source_test.mbt \
  src/query_program/pipe_scope_test.mbt \
  src/query_program/order_property_paths_test.mbt
node scripts/local-checks.mjs test node -- scripts/unnest-source-input.test.mjs
```

Selected JS passed 17/17 at `focused-test-MI4E8u` / `run-Ht8Bsp` before the
final test/evidence commit. Four source variants match an independently authored
complete Program. Additional checked sources cover the whole nullable object,
WHERE, star EXCEPT, SET/current versus original slots, AS, unselected property
ordering and grouping. Three removed-receiver cases require the exact
`Expression(UnknownReference)` issue. The previous empty object-star refusal
becomes a positive case; the public negative case now selects a missing field.

The public fixtures are registered in the existing normal UNNEST corpus and
its narrow runner. They compare independent rows, ordered column contracts,
nullability, hidden-column absence, stream completion and same-request reuse.
Fresh normal five-package Local/HTTPS execution remains to be recorded for the
committed SHA. Selected local tests are not CI success. Full Core, Wasm/native
runtime, full packed campaign, proof and performance suites are not required
local diagnostics and have not been run for this change.

## First packed probe and canonical object fixture correction

The normal five-package set at `25302bd878b0d4fb6c930c3e0ea2b0b7879e3b46`
passed producer generation, twelve profile checks, README Local/HTTPS and the
expected missing-generated-asset refusal. The UNNEST corpus then passed its
first nineteen Embedded Local cases, including the independent STRUCT JSON
control, stars, qualified star, empty and NULL arrays. It stopped at the
whole-value describe comparison. HTTPS corpus execution was not reached.
Receipt: `worktrees/.codex-scratch/public-query-evidence-pEJszN`.

The independently authored expected object contract omitted the required
canonical `additional_properties:false`. Author parameter syntax omits this
closed-object default, whereas checked contracts must contain it; see
`value_contract/admission.mbt`, `value_contract/encode.mbt` and the independent
object vectors in `value_contract/corpus.generated_test.mbt`. Add that field to
whole-object and nested-object expectations from this common contract, without
changing input values, expected rows, nullability, order or product code.
The failed probe remains historical evidence, not completed public acceptance.
