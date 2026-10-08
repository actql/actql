# Conditional aggregate-local ordering

Adopted main: `e28876c77436689dfb388122aacb257fff83cd6a`.
Destination: main. No unmerged parent dependency or compatibility fallback.

## Independent discrepancy and repair

```sql
SELECT STRING_AGG(name, '|' ORDER BY COALESCE(payload.score, 0) NULLS LAST, id) AS names
FROM objects
```

The parser already accepts this source. An independently authored complete
Values Program derives the existing `coalesce(property(score, field(payload)),
literal(0))` key and passes the ordinary checker, whereas the source counterpart
fails before the repair. The initial focused run passed **1/2**:
`run-EwueAF` / `focused-test-dhB3OU`. This is compiler/checker evidence, not a
pre-repair public execution claim.

The selected [GoogleSQL aggregate-call rules](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/aggregate-function-calls)
permit ordering expressions, with DISTINCT keys denoting the argument.
[Conditional expressions](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/conditional_expressions)
retain their existing lazy common-expression meaning. Reference inspection is
not differential execution against a Google service.

The existing `aggregate_order_fields` connection now admits COALESCE, IFNULL,
IF, NULLIF and searched CASE when their complete operand trees contain only
admitted literals, references, parameters, static properties, numeric signs,
comparisons, Boolean operations, NULL/Boolean predicates and those conditionals.
Quoted function names retain the existing single-part, case-insensitive lookup.
Arity, signatures, properties, parameter binding and ordering types remain the
responsibility of the ordinary expression lowerer and common checker.

This admission guard does not evaluate values, infer types or implement a new
demand owner. It scans the bounded, postorder source AST without recursive
evaluation. The original expression goes to `append_with_properties` and the
existing private order-slot allocator. Keys are reused only within the same
immutable GROUP input resolver; hidden HAVING inputs retain their own scope.
No expression is replaced with a column, default, constant or inferred ordinal.

The independent public input includes duplicated id=2, nullable object/member
values and a NULL aggregate argument. With a fallback of zero the expected
sequence is `c|b|b|a`; dropping COALESCE gives `b|b|a|c`. Coalescing the object
receiver instead gives `b|b|c|a`. Current and pre-SET snapshot inputs give
`a|c|b|b` and `c|b|b|a` respectively. Per-call opposite orders, an explicit
aggregate filter, typed parameters, empty input and DISTINCT also have authored
expectations. Private fields cannot appear in the public Result.

## Remaining computed-key boundary

This repair does not claim arbitrary computed aggregate ordering is complete.
For example:

```sql
SELECT STRING_AGG(name, '|' WHERE FALSE ORDER BY id / (id - id), id) AS names
FROM objects
```

The adopted common aggregate evaluation law is filter, demanded argument,
NULL exclusion and aggregate-local ordering. `lower_aggregate_resolved` and
`relation_typing/aggregates.mbt` currently pass column order terms. The existing
`AggregatePreparation` collects contributors with that demand law and sorts
their input-row keys; it does not accept order-key expression frames.
Hoisting a divide into an unconditional derive introduces a division-by-zero
failure on excluded rows. Hoisting the argument/filter too would also move
their evaluation across independent aggregates, change failure order and risk
duplicate evaluation. No such rewrite is introduced.

A common-owner extension for arbitrary keys would need checked, aggregate-local
order expressions evaluated once at the specified contributor boundary, with
their existing frame/work/root/capacity/cancellation responsibilities retained.
The counterexample above should yield nullable `names = NULL`, and a demanded
nonzero-denominator counterpart must retain its requested order. This is a
concrete remaining connection requirement, not a permanent language restriction
or a request to copy the aggregate executor into the Frontend. The current
Frontend explicitly refuses potentially failing operands, including inside
otherwise lazy conditionals, rather than claiming that laziness makes hoisting
equivalent.

## Focused evidence and public obligations

Final affected JS tests: **23/23**, `run-NZGxDt` / `focused-test-ZmbFLc`.
Node fixture/profile tests: **20/20**, `run-o21NNT` / `focused-test-PTsWTb`.
Two earlier post-repair attempts passed 22/23 because the new test incorrectly
expected one-argument COALESCE to be refused; the installed common contract
allows it. That erroneous test expectation was removed, without changing the
product or public row expectations. The original failure records remain.

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/aggregate_conditional_order_test.mbt \
  src/query_program/aggregate_signed_order_test.mbt \
  src/query_program/aggregate_property_order_test.mbt \
  src/query_program/distinct_aggregate_order_test.mbt
node scripts/local-checks.mjs test node -- \
  scripts/aggregate-conditional-order-source-input.test.mjs \
  scripts/aggregate-signed-order-source-input.test.mjs \
  scripts/aggregate-property-order-source-input.test.mjs \
  scripts/public-query-profiles.test.mjs
```

Read-only compilation-manifest validation passes with unchanged grammar
`sha256:a85a3517afd7a705e99e746f5a08332370b072ddc77868372db19b977ee87ecb`.
No syntax, type, expression law, wire, schema, canonical identity domain or
serialization contract was changed. Normal Programs retain their current
identity inputs; the newly generated Programs include their authored derives.

The **13 new normal and five refusal cases** are in both the default packed
corpus and the existing `--aggregate-property-order-only` selection. The complete
selected corpus, including existing signed/property/parameter controls and the
expected demanded-argument failure, must pass through freshly packed Local and
real HTTPS. Existing checks retain rows, Result.describe types/nullability and
column order, one Source session, private-column exclusion, unchanged-request
resend/reread without reacquisition, and admission/provider-I/O zero on preparation
refusal. Public acceptance, package identities and required CI are pending at
this implementation commit; focused success does not establish them.
