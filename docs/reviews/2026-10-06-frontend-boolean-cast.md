# BOOLEAN CAST source alias

Base: `3ebbbf5c8f8e06d25bcf5b5b8f5a6b83264ddca9`. Target: main, no unmerged dependency.

GoogleSQL defines BOOLEAN as an alias of BOOL:
https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/data-types#boolean_type.
The Frontend accepted BOOL but rejected BOOLEAN before generating the ordinary
Program. Both spellings now resolve to the existing `CastType::Boolean`. No
new conversion, common type, evaluator or Host route is introduced.

## Independent counterexample and verification

The complete hand-authored Program in `cast_alias_test.mbt` uses the existing
boolean cast, preserves a typed NULL, and passes the normal checker. Before
changing the parser, the new test failed (0/1) on BOOLEAN after its BOOL control
passed: `_build/local-checks/attempts/run-FiVQ77`, focused evidence
`_build/focused-evidence/focused-test-UhkdzY`.

After the change:

- Selected JS tests: `cast_alias_test.mbt`, `source_free_test.mbt`,
  `query_syntax/expression_test.mbt`: 14/14, guard `run-r412mh`, evidence
  `focused-test-JthL1e`.
- Node tests: `boolean-cast-source-input.test.mjs`,
  `sga-query-call-contract.test.mjs`, `client-values-run-materials-vector.test.mjs`:
  5/5, guard `run-Nuulkx`, evidence `focused-test-pngNR7`.
- Actual Values issuer: `client_values_run_materials_wbtest.mbt`: JS 1/1,
  guard `run-SchA3U`, evidence `focused-test-GClTWN`.
- Read-only compilation manifests, document metadata, canonical JSON and
  spec-family checks passed. Spec-family conformance remains false.

All tests use `node scripts/local-checks.mjs test node|moon -- ...`; Moon tests
select `--target js` and exact files. Native/Wasm/full Core/manual CI are not run.

The ordinary packed corpus and its `--boolean-cast-only` selection include
8 successes (including an independent JSON control), 4 preparation refusals,
and 1 admitted invalid-string cast failure per Local/HTTPS transport. Expectations
include values, declaration-order columns, nullability, empty typed Result,
parameters, Pipe scope, no Source I/O, and existing resend/reattach behavior.
Public execution evidence will be recorded after the clean-HEAD package run.

## Identity impact

The normative query rule bytes change, so the grammar manifest and dependent
Run identity change; the machine Program, cast law and registry do not.
The independent normative-preimage calculation produces grammar CID
`sha256:5ac68c0bb19d569209191ad0131672abca12b8d520a800c7bc523fb0ab957c20`
and Values Run CID
`sha256:5d0c79e01623a60b1ab0f1f9e46f4ed395dae07ace32f9e8e6f46f8dcce1385b`.
The complete preceding main grammar body and its Run vector remain fixed in
independent tests; issuer expectations use the independently hashed new vector.

## Separate remaining boundaries

This closes the type-name alias, not full GoogleSQL CAST conformance. Existing
common STRING-to-BOOL conversion accepts lowercase `true`/`false`; wider
case-insensitive value conversion is not changed by this PR.

ARRAY construction was investigated separately. Normal common typing accepts
`array` and `empty_array`, but current `lowering_relation/expression.mbt` lacks
both in `expression_tag`. A retained bridge built at
`fd6aa6885349cf427548db596a4a048f6c67b2ac` confirms preparation rejection
`ExpressionNotImplemented("array")` and `ExpressionNotImplemented("empty_array")`
for independent JSON Programs. This is not a clean current-main execution claim.
The affected lowerer blob is identical at that build revision and current base
(`12a447caaf1fe48f838eb06e212148b1a56168ce`). No Frontend ARRAY syntax,
JSON-literal workaround or duplicate evaluator was added. The minimal diagnostic
is `/private/tmp/actql-b-array-prepare-probe-20261006.mjs` with its `.log` sibling.
