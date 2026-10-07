# Declared object UNNEST field expansion and STRUCT coverage boundary

Adopted main: `3a01ebcea5af032bb22cfe5b55132d0e36ad4b77`.
This independent Frontend unit does not depend on Pipe JOIN range PR #759 and
changes no common Owner or Program wire contract. The normative query-rule
change updates the compilation grammar manifest and containing Run identities.

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

The connected value type is the existing named-object parameter contract,
whose fields are sorted by the common contract's UTF-16 canonical ordering
(`value_contract/parameters.mbt` and `value_contract/admission.mbt`). The new
independent lowering check reverses authored `label`/`id` JSON members and
requires the same Program and `id,label,position` output. This is not
author-selected STRUCT order. The ordered/anonymous/duplicate-field STRUCT
dependency remains recorded in [the common-contract gap](2026-10-07-struct-contract-gap.md).

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

## Submitted execution and supplemental completion

At `f405e2749705e897f08156b742bfd04c833f7052`, ordinary fresh five-package
acceptance completed 24 Local positives and all 11 refusals, then 21 HTTPS
positives before its unchanged 900,000 ms command deadline. Receipt
`public-query-evidence-yEclOZ` records `ETIMEDOUT`/`SIGKILL` and remains
incomplete, rather than a successful campaign. No row/schema failure appeared.

The unchanged remaining HTTPS fixtures (`immutable-range`, `data-binding`,
`nested-top-level`) and every refusal passed with the same five producer
tarballs in a fresh external installation. The supplement reused the ordinary
fixture, public assertions, Host setup/capacity, admission and native-I/O
observations without product overlays or Program corrections. Receipt
`public-query-evidence-IeZhqY` is complete/passed, with 3 accepted Runs and
provider I/O 0. Its earlier sandbox invocation stopped at loopback listen
`EPERM` before source submission (`public-query-evidence-oUhep3`); that is not
a product rejection. The final fixture additionally checks a non-NULL string
property beside a NULL element and NULL property; final-revision execution is
recorded separately, not inferred from the earlier receipts.

## Integrated public execution and manifest follow-up

Normally merged main `c0f4410834c13e1f6cd878902ad06e1ec5d84846` produced
`dce6c8d5564652e15e9813fc53adb59d02c9d021`. Focused JS passed 9/9 there,
including the adopted immutable Pipe JOIN ranges. Normal five-package packing
and external Embedded Local/HTTPS UNNEST acceptance passed 25 positive and 11
refusal cases per transport. Independent rows, ordered contracts, NULL behavior,
non-NULL strings, private-column absence, request reuse and refusal-before-
admission/I/O assertions were retained. Receipt `public-query-evidence-RLpcHv`
is complete/passed; command 008 exited 0 within its existing 900,000 ms budget.
The disposable installation was removed after evidence capture.

The subsequent read-only compilation-manifest check found a missing normative
rule-pin update. Regenerate with `compilation-manifests.mjs`, update the explicit
machine/document imports, and regenerate the canonical/spec-family outputs.
The independently hashed query-rule preimage gives grammar manifest
`sha256:a395e9d881fd75019ff99db18016a4cf72f19f14f52856b8f313462e0489c09a`.
The independent hand-assembled Values oracle gives containing Run identity
`sha256:31dc7d61b6fe40c4662a836eecc194ef96aa50548b8327a49b4d95dd0d32f896`;
retain its predecessor vector. Values Unit, bound proof and Result Plan are
unchanged. Old Runs are not reinterpreted under the new grammar identity.

The successful `dce6c8d55` packages precede that pin correction. They are not
final-revision package evidence; normally generate and check the corrected
revision before claiming final public execution. Exact-HEAD automatic CI run
37579755151 failed at select-targets/check with empty steps; product jobs were
skipped and its cause is not established. Required CI remains unexecuted.
