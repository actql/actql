# Aggregate-local ordering of typed object properties

This Frontend correction starts from main
`64046e37a1cadb2148edeab7cbf85b96d125b518`. It connects static typed-object
property paths in collection aggregate ORDER BY to existing derive/group
operations. It does not introduce an aggregate executor or change a common
type, value, identity, capacity, cancellation or serialization contract.

## Counterexample and independent expectation

```sql
SELECT STRING_AGG(name, '|' ORDER BY payload.score NULLS LAST, id) AS names
FROM objects
```

The independent complete Program in
[the regression fixture](../../src/query_program/aggregate_property_order_test.mbt)
projects `payload.score` with the existing `property` expression and passes that
field to the aggregate's existing `order_by`. The normal checker accepts it.
The unmodified main lowerer instead resolves the whole path as an input column
and returns `UnknownColumn`. Bounded pre-fix run `run-jYeGms` records 0/1 passing
with that exact refusal. Earlier `run-Zt6ION` records the same source failure at
an unwrap; `run-wRGeLs` is an author diagnostic compile failure, not product
execution evidence.

For rows with names `b,a,c,NULL`, payload scores `10,20,NULL,NULL`, and IDs
`2,1,3,4`, the expected STRING_AGG value is `b|a|c`. The NULL argument is
excluded; a NULL receiver remains a NULL order key. The public fixture repeats
ID 2, so its independent expected value is `b|b|a|c`. Reversing only this
aggregate's key order yields `c|a|b|b`.

GoogleSQL's [STRING_AGG reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/aggregate_functions#string_agg)
describes non-NULL argument concatenation and aggregate-local ordering. Its
[field access operator](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators#field_access_operator)
admits STRUCT property access. ActQL's authoritative common rules are the
typed-access and additional-aggregates sections of `docs/spec/language.md`.
This is not a claim of complete GoogleSQL aggregate conformance. In particular,
ARRAY_AGG keeps ActQL's existing key, NULL-exclusion, empty-result and resource
rules; this change does not reinterpret them.

## Connection and evaluation boundary

- `query_aggregate_order.mbt` resolves direct columns and receiver prefixes in
  the same immutable GROUP input scope as aggregate arguments. SELECT sibling
  aliases do not replace those inputs.
- Static property paths become private derive slots. The existing common
  checker determines receiver/member type, NULL propagation and orderability.
  A missing member or non-object receiver remains a static error.
- Repeated paths within that scope share a total property projection. Each
  aggregate retains its own direction and NULL placement. Pipe current slots
  and prior range snapshots stay distinct.
- The existing name allocator avoids collisions with physical fields, keys and
  projection names. GROUP removes private keys before Result publication.
- Aggregate argument expressions remain inside the aggregate. Arbitrary order
  calls/arithmetic remain unsupported; they are not hoisted across demand or
  turned into a new permanent language restriction.
- ARRAY_AGG requires real key evidence. An initially unasserted array control
  was refused by common SourceView preparation (`run-Ko4zN3`, narrowed diagnosis
  `run-c44TC8`); it was not declared a Frontend bug. The positive control
  explicitly uses existing `ASSERT UNIQUE BY (id)`. Its public fixture also
  explicitly orders and limits the input to four rows. Neither assertion nor
  limit is synthesized by the compiler. Diagnostic `run-iDhk2q` failed to
  compile an attempted debug printer and supplies no product evidence.

## Verification boundary

Focused editing checks: `run-p49zI6` passed 7/7 selected Program/checker tests;
`run-aTUKjy` passed 11/11 fixture/profile Node tests. Earlier `run-Ko4zN3`
passed 5/6, with the unasserted array control refused as described above.

The ordinary packed corpus registers the same independent controls as the
focused `--aggregate-property-order-only` selection. It compares full Result
columns, values and order; checks one acquisition, replay of the same request
and Result rereading; and checks pre-admission refusals and demanded argument
failure without publishing a Result. The source fixture includes independent
JSON Programs, SQL/Pipe qualification, opposite per-call ordering, SET current
versus snapshot values, SELECT sibling collisions, WHERE, duplicate values,
NULL receivers/members/arguments, empty input and an explicitly keyed array.

Packed execution is recorded separately after a clean-SHA normal five-package
pack. Editing tests are not public execution or hosted CI evidence. No full
Core, Wasm/Native run, proof campaign, performance test or Cloud acceptance is
part of this unit. D/H/A ownership work remains independent.
