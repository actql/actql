# STRING_AGG default delimiter

Owner: B. Base: main `edaa27e9733572b8b26944a28d5d646f6d827381`.

## Counterexample and adopted rule

```sql
SELECT STRING_AGG(name ORDER BY payload.score NULLS LAST, id) AS names
FROM objects
```

The existing parser required an explicit comma and delimiter, rejecting this
input before lowering. A separately authored complete Program with
`string_agg`, delimiter `","`, the original field/property order and byte limit
passes the ordinary checker. The pre-fix focused regression failed 0/1;
evidence: `_build/focused-evidence/focused-test-z2fe5f`.

The pinned [GoogleSQL aggregate reference](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/aggregate_functions.md#string_agg)
defines an optional delimiter, defaulting to a comma, excludes NULL
contributions, and returns NULL for empty/all-NULL input. The
[official documentation](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/aggregate_functions#string_agg)
also documents these rules. Reference examples are not a live differential
execution against a Google service.

## Implementation and independent expectations

`QueryParser::aggregate` consumes a delimiter only when a comma follows the
argument; otherwise it records the explicit default `","` in the existing AST.
The existing lowerer and common aggregate receive their ordinary delimiter
argument. Neither the following WHERE nor ORDER tokens are consumed as a
delimiter. Authored empty/newline delimiters remain unchanged.

No checker, execution owner, capacity limit, serialization, schema, law pin or
Graph contract changes. The existing STRING-only, literal-delimiter, explicit
aggregate ORDER profile remains limited; this is not general STRING_AGG
conformance. The generic expression grammar and pinned query rules are unchanged.
Existing JSON Program semantics and machine-input identities are unchanged;
newly accepted text lowers through the usual Program and identity calculation.

The complete MoonBit expected Program is handwritten independently of compiler
output. SQL implicit/explicit comma and Pipe implicit comma compare against it
and pass ordinary checking. Additional syntax tests preserve filter/order and
require the specific typed syntax reason for invalid explicit delimiters.

Public cases extend the existing property-order corpus and ordinary packed
route. They retain the original ten normal, four refusal and one execution
failure cases. Seven new normal and three new preparation-refusal cases include
an independent JSON comma control, SQL/Pipe omission, empty delimiter, aggregate
WHERE, empty input and all-NULL contributions. Expected rows are written from
the ordered contributions `b,b,a,c`, retaining both b values and excluding NULL;
empty delimiter yields `bbac`, filter yields `b,b,a`, and empty/all-NULL yields
SQL NULL. All expose just `names`, a nullable string, with no internal sort key.

## Focused verification

With the pinned Node/MoonBit PATH and MOON_HOME:

```sh
node scripts/local-checks.mjs test moon -- --target js src/query_program/string_agg_default_delimiter_test.mbt src/query_program/aggregate_property_order_test.mbt src/query_syntax/string_agg_delimiter_test.mbt src/query_syntax/aggregate_filter_test.mbt
node scripts/local-checks.mjs test node -- scripts/aggregate-property-order-source-input.test.mjs
```

JS: 13/13, `_build/focused-evidence/focused-test-E7EM93`.
Node: 5/5, `_build/focused-evidence/focused-test-eavdDC`.
These are focused execution, not full Core or CI success.

## Public acceptance

Source SHA: `697f18fc11a971329868b38c77dc65d4b8969b2a`. Normally prepacked
manifest: `/private/tmp/actql-b-string-agg-default-697f18fc1-pack/packed-client-packages.json`.
The final report-only commit changes no runtime or acceptance fixture input;
the execution evidence remains tied to the source SHA rather than being renamed.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-string-agg-default-697f18fc1-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-string-agg-default-697f18fc1-pack node scripts/test-packed-public-query.mjs --aggregate-property-order-only
```

Both commands used pinned PATH/MOON_HOME, the existing private npm cache,
offline dependency installation and optional dependencies. No prepack was
skipped and no adapter overlay or lowered-Program patch was used.

External Embedded Local and public HTTPS each passed 17 normal cases, seven
preparation refusals and one deliberate demanded-expression execution failure.
Named Result rows, describe type/nullability/column order, stream completion,
one Source acquisition, same-request Run identity and no acquisition on
reread/attach were checked. Refusals verified zero admission/provider
acquisition; the execution failure verified no partial Result.

Receipt: `worktrees/.codex-scratch/public-query-evidence-kqjMMY`, passed/complete,
no evidence errors; this run's temporary installation was removed. Command 008
exited 0 in 276334 ms. The existing runner also passed 11 profile checks and
README/SDK-asset smoke checks. Protected untracked `review-artifacts` explains
the receipt's dirty flag; tracked source and all package build inputs were clean.

| Package | SHA-256 |
|---|---|
| client-wire | `0212e9f37cde525589a0e8d48b62151e73ce53153ef75948974cb9f672659523` |
| sdk | `fe085d7d7e2cce344c2c4daf18f33ca477dcee9189e96552816cf9eee6b10972` |
| run-host-core | `c30ec73dbc24d074d9d887b0eaab3387b95d55cd4b5ac11879cfe5775f7542de` |
| local-node | `8222ae51ec98e8588fe10fd0daf9ac81fc42383d1fbc619cf8d906269f8cc9fa` |
| node | `89a340b9d0a80c4ade483e471c06a5503f81c347ced3a17f3c4e4d4a21b1eb64` |

Keep Draft until review and required verification. Full Core, Wasm/Native,
proof, broad packed, performance and Cloud execution are unverified. No manual
CI rerun or PR merge is authorized by this report.
