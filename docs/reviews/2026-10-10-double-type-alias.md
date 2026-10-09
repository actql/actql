# DOUBLE numeric type alias

## Selected contract and counterexample

Baseline: `584b3a6144d4a8053ca4a541ef042a6e17c674e9` (`origin/main`).
The selected GoogleSQL language reference is
[`d82db99a923a46571f543a13899dc791a7b6f743`, Floating point types](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/data-types.md#floating_point_types).
It defines FLOAT64 as an alias for DOUBLE. FLOAT/FLOAT32 are separate types;
this change does not claim those types or every deployed Google service.

```sql
SELECT CAST(1.25 AS DOUBLE) AS value,
       CAST(NULL AS DOUBLE) AS missing,
       ARRAY<DOUBLE>[2, NULL, 2] AS items
```

The independently authored expected Program uses the existing `cast` target
`{"type":"number"}` and the existing `array` / typed `empty_array` / lazy `if`
contracts. It passes ordinary checking. Before the change, the CAST and ARRAY
source tests fail while parsing DOUBLE; FLOAT64 controls precede DOUBLE in each
test. Evidence: `_build/local-checks/attempts/run-AmUrzy` and
`_build/focused-evidence/focused-test-kTMkTD` (0/2).

## Implementation boundary

Only the CAST-target and ARRAY-item parser branches add DOUBLE to their
existing FLOAT64 alternatives. Both still issue the same parsed numeric type,
so ordinary lowering, checking, evaluation and Result typing remain shared.
There is no new type, conversion, safe-cast behavior or execution Owner.
Unquoted ASCII case-insensitive spelling is supported. Quoted type names,
FLOAT/FLOAT32, undeclared or mismatched parameters, and incompatible annotated
ARRAY items remain rejected through the existing preparation boundary.

Independent complete-Program fixtures cover CAST and ARRAY, mixed case, NULL,
empty typed arrays, duplicate items and ordinary checking. The existing public
ARRAY cohort adds a JSON control, both type spellings, nullable parameters,
empty Results, string conversion, lazy-demand failure avoidance and Pipe scope.
Its complete cohort is 21 positive and 16 preparation-refusal cases. Expected
rows, declared column order and full column contracts are authored independently.
The existing ordinary campaign includes this cohort; it is not narrow-only.

## Grammar and identity

The EBNF and query rules change their compiler manifest pin to
`sha256:b3688a442f39d99e7890d05e267c807914f2253c8a54b6de889885d7852af4b4`.
Normal manifest, metadata and canonical-vector generators update their reviewed
outputs. `pre-double-type-alias-grammar.json` preserves the complete predecessor
manifest and independently reconstructed template, executable, compiled and Run
preimages. Tests rehash those bodies independently and retain the prior Run CID
`sha256:fa57a9c0f667cae5597a30f9cf4606c86d3c15620526d757f7942e16129b01bf`.

The current Values Run vector is independently reconstructed as
`sha256:0af1a043d6f8054e2c51c595c929fea4442f08a259924f738e4c25dd2fe6f3a4`.
The Values Program, Unit, bound proof and Result Plan identities are unchanged.
Old Runs are not reinterpreted or rewritten under the new grammar pin.

## Focused validation

Using pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_syntax/double_type_alias_test.mbt \
  src/query_syntax/array_constructor_test.mbt \
  src/query_program/double_type_alias_test.mbt \
  src/query_program/cast_alias_test.mbt \
  src/query_program/array_constructor_test.mbt \
  src/run_publication_host/client_values_run_materials_wbtest.mbt
node scripts/local-checks.mjs test node -- \
  scripts/array-literal-source-input.test.mjs \
  scripts/compilation-manifests.test.mjs \
  scripts/sga-query-call-contract.test.mjs \
  scripts/client-values-run-materials-vector.test.mjs \
  scripts/frontend-profile.test.mjs
```

- JS: 18/18, `run-m7rfZd` / `focused-test-zVCk4r`.
- Node: 28/28, `run-0HVUTS` / `focused-test-uVARFg`.
- Read-only manifest, document metadata, spec-family and canonical-vector checks
  pass; 382 canonical identities agree with the regenerated test source.
- Changed MoonBit files formatted with `moonfmt`; `git diff --check` passes.

An initial refusal assertion used Eq on a diagnostic without that trait
(`run-eS9Qps`, no tests executed). A subsequent exact-message assertion overlooked
the existing distinction between quoted and unsupported type names
(`run-HYTQIz`, 17/18). The final test preserves both exact existing reasons.
Neither failure required a product diagnostic change.

Packed Local/HTTPS execution and exact submitted-SHA CI are recorded separately
in the PR after normal clean-HEAD packing. The focused checks alone do not claim
public execution, Wasm/native coverage, complete ARRAY/CAST support or full
Frontend conformance. No full Core campaign, manual CI retry or merge is run.
