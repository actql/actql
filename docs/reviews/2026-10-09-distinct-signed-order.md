# DISTINCT signed aggregate argument identity

Normally merged main: `4900085d1a08461c097652ecced47f920ee15f09`.
Stacked parent: #1030, `de6b5b8294832aa6f98a3171f48252577b082425`, retaining
#1026, #1023 and #1022. Final destination is main after those dependencies land.

## Independent discrepancy and repair

```sql
FROM objects
|> ASSERT UNIQUE BY (id)
|> AGGREGATE ARRAY_AGG(DISTINCT -id IGNORE NULLS
                      ORDER BY -objects.id DESC) AS items
```

Both expressions denote the same signed input column. The existing DISTINCT
comparison resolves static references and properties, but falls back to raw
expression syntax for unary nodes. Qualification therefore causes rejection
before the existing aggregate owner receives a valid ordinary Program.

The independently authored Program preserves the unique assertion, derives
`negate(field(id))` as a private order key, and supplies that original expression
to the distinct ARRAY_AGG with the declared direction. It passes ordinary
checking. The pre-repair selected test passed 1/3: both source counterparts
failed compilation (`run-vEeHzR` / `focused-test-MJ9rZj`). Earlier checks without
the required unique assertion failed the control itself and are not evidence of
this Frontend defect. The final complete expectation uses the fixed test
ceiling of 1000 and the adopted DESC NULLS LAST default; these are derived from
the declared limits and ordering contract, not from issued runtime identities.

The repair retains the ordered unary sign sequence while comparing the same
resolved input receiver and static property suffix. Different signs, different
receivers, SET snapshots and range/object collisions remain unequal. It does
not simplify numeric expressions, infer injectivity, manufacture a candidate
key or change demand. The existing expression lowerer, checker, aggregate,
ordering and capacity owners remain authoritative.

## Focused checks

Affected JS checks: **16/16**, `run-FpwLLn` / `focused-test-DBDg9k`, including the
fixed Values Run-material caller. Node fixture, registration, profile, manifest
and independent identity checks: **27/27**, `run-3KjVmD` / `focused-test-zjDnFb`.

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/distinct_signed_order_test.mbt \
  src/query_program/distinct_aggregate_order_test.mbt \
  src/query_program/aggregate_signed_order_test.mbt \
  src/run_publication_host/client_values_run_materials_wbtest.mbt
node scripts/local-checks.mjs test node -- \
  scripts/distinct-signed-order-source-input.test.mjs \
  scripts/distinct-aggregate-order-source-input.test.mjs \
  scripts/aggregate-signed-order-source-input.test.mjs \
  scripts/public-query-profiles.test.mjs \
  scripts/client-values-run-materials-vector.test.mjs \
  scripts/compilation-manifests.test.mjs
```

## Main integration and independent pins

Merge `1c8cc8de6` retains main's adopted set, Pipe DISTINCT, grouped extrema,
COUNTIF DISTINCT and analytic frame cases alongside the parent fixtures.
The compilation, spec-family and canonical generators updated merged inputs.
The resulting grammar CID is
`sha256:4943caba75b011ab9aebfc07d4f30ea4a5aefa72c50bc2eab44724cc3e6aaff9`.
The independent complete Values preimage yields Run CID
`sha256:093170ff7e898c3ef58a1fd5d3930222b06aafd64bda70ab62f311d1b9ac56df`.
Previous grammar/Run vectors remain bound to their own unchanged dependency
generation; Unit, Proof and ResultPlan identities are unchanged.
No product-issued CID supplies these expectations. This repair changes no
public grammar or common semantic contract.

## Public acceptance and remaining coverage

The existing normal corpus and `--distinct-aggregate-order-only` cohort include
ten new normal and five new refusal cases, alongside the parent's ten normal
and seven refusal cases. Independently authored source and JSON controls check
signed values, duplicate argument values, nullable objects, positive/nested
signs, filtering, empty input and input/range/snapshot distinctions. Explicit
key assertions, LIMIT 4 and ordinary Host ceilings are retained.

Normal exact-HEAD five-package production and external Local/HTTPS execution
are pending at this evidence commit. The PR body records the eventual source
SHA, tarball digests, retained logs and actual results separately. Existing
public checks compare Named Result rows and Result.describe contracts, exclude
private fields, and verify one Source read, resend/reread without reacquisition,
plus zero Run admission/provider I/O on preparation refusal.

Required CI, full Core/Native/Wasm/Cloud and the broader computed-order profile
remain unverified. No manual CI rerun or merge is part of this unit.
