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

Pending a clean source commit and its normally prepacked five-package manifest.
Use the existing `--aggregate-property-order-only` runner; compare Named Result
rows, describe type/nullability/column order, stream completion, one Source
acquisition, same-request Run identity and no acquisition on reread/attach.
Preparation refusals require zero admission and provider acquisition. Preserve
the existing demanded-expression failure with no partial Result.

Keep Draft until review and required verification. Full Core, Wasm/Native,
proof, broad packed, performance and Cloud execution are unverified. No manual
CI rerun or PR merge is authorized by this report.
