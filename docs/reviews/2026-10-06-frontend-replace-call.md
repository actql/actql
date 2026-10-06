# GoogleSQL STRING REPLACE connection

## Counterexample and implementation

At main `c42f1647823cd27115963270aba82623c5dbffab`, the independently authored
Program for `SELECT REPLACE('banana', 'ana', 'X') AS value` passes the ordinary
checker, while the source compiler refuses the function. The pre-repair focused
Program regression failed (0/1); its expected Program was checked first.

The fix maps the three-argument public `REPLACE` call to the existing common
`replace` expression. It preserves argument order, parameter references and
ordinary clause name resolution. It adds no evaluator, Host route or fallback.
The [selected GoogleSQL STRING contract](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/string_functions#replace)
and existing common rules require literal replacement, non-overlapping matches,
empty-search identity and SQL NULL propagation. BYTES and explicit collation
remain separate coverage gaps. This scalar function is independent of SELECT
star REPLACE.

## Independent evidence and public obligations

The source-free lowering regression compares the complete generated Program
with hand-authored JSON. Expression regressions check argument order, exact
Unicode/CR/LF preservation, parameter references, arity and unsupported namespace
reasons. Focused JS tests including the existing IFNULL caller passed 5/5;
selected fixture/profile Node tests passed 11/11.

The public fixture defines 11 normal cases (one independent JSON control),
7 preparation refusals and one demanded execution failure, per Local/HTTPS
transport. It covers repeated/overlapping matches, empty search/replacement,
Unicode and line endings, each nullable operand, typed parameters, SQL/Pipe
current versus original columns, duplicate rows, typed empty input and lazy
conditional demand. Normal cases require independently authored rows and exact
Result.describe column types/nullability/order, stream completion, no hidden
columns, shared acquisition counts and existing retransmission/reattachment
semantics. Preparation refusals require zero Run admission/provider I/O;
demanded failure must publish no Result. These cases are registered in the
ordinary packed corpus as well as `--replace-call-only`.

Public execution is pending at this source commit. Parser, checker and focused
fixture success must not be reported as packed execution or CI success.

## Identity and validation scope

Only the query-text normative rules change; the generic call grammar, Program
schema, common expression laws and Values Program remain unchanged. The new
grammar manifest is
`sha256:4d5820302b1e28cef89cfabb29b2aa0607d7b432ebfa956d50d57cf4e24c8439`.
The independently computed Values Run closure is
`sha256:f1c2e4b9c9614cf5d1684d263b1182e9e6603ac9c4e668637161e811e664b9ba`.
The previous grammar and Run preimages remain immutable historical vectors.
Dependent metadata, generated pins and canonical vectors were regenerated from
source. The four focused manifest/vector/import files passed 12/12 and the
actual Values Run issuer regression passed 1/1. Read-only compilation manifest,
metadata, canonical JSON and spec-family checks passed; spec-family continues
to report `conformance:false`.

Commands used the pinned MoonBit toolchain and `scripts/local-checks.mjs`:

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_expression/replace_call_test.mbt src/query_expression/ifnull_test.mbt src/query_program/replace_call_test.mbt
node scripts/local-checks.mjs test node -- scripts/replace-call-source-input.test.mjs scripts/ifnull-source-input.test.mjs scripts/public-query-profiles.test.mjs
node scripts/local-checks.mjs test node -- scripts/sga-query-call-contract.test.mjs scripts/client-values-run-materials-vector.test.mjs scripts/compilation-manifests.test.mjs scripts/spec-family-imports.test.mjs
node scripts/local-checks.mjs test moon -- --target js src/run_publication_host/client_values_run_materials_wbtest.mbt
node scripts/compilation-manifests.mjs
node scripts/update-document-metadata.mjs
node scripts/check-canonical-json.mjs
node scripts/check-actql-spec-family.mjs
```

Full Core, Wasm/native execution, proof campaigns, all packed cases and performance
checks were not run. This unit does not claim complete Frontend migration.
