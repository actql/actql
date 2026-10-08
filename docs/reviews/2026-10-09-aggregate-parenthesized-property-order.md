# Parenthesized aggregate ORDER property receivers

Inspected main: `80ca8ab23202cde18123e9a1a790bb7c5f308aa8`.
This connects an already parsed static property expression to the existing
common projection/checking path. It adds no executor, numeric/NULL rule,
capacity relaxation or provider-specific fallback.

## Independent counterexample

```sql
SELECT STRING_AGG(name, '|' ORDER BY (payload).score NULLS LAST, id) AS names
FROM objects
```

The independently authored complete Program in
`aggregate_property_order_test.mbt` derives `property(score, field(payload))`
before its collection aggregate. It is normally checked. The Frontend already
produces that Program for `payload.score`, but rejects `(payload).score` because
`aggregate_order_fields` requires a Reference AST after stripping outer
parentheses, overlooking explicit Property AST nodes. The added positive
counterexample failed **7/8** before repair (`run-LW2gd7` /
`focused-test-CswHL7`); no public wrong-result execution is claimed.

## Minimal connection

Recognize static Property/Parenthesized chains ending in a Reference receiver.
Keep the original AST when delegating to `append_with_properties`; do not
concatenate member names into a range-qualified path. An explicit property
always requires projection even when its receiver resolves directly to a slot.
Existing direct field reuse, immutable input scope, work checks, private slot
allocation and shared projection reuse remain. Common checking retains object
types, member presence and NULL propagation. Arbitrary computed order keys
remain outside the current connected subset, not a new permanent language rule.

The fixed test compares SQL and Pipe forms, nested parentheses and a quoted
member with the same independently authored complete Program. A public range
collision uses `other.score AS score` and range alias `payload`: the explicit
`(payload).score` must still read the object column. Correct concatenation is
`b|b|a|c`; flattening it to scalar `payload.score` would yield `a|c|b|b`.
Duplicates, nullable object/field, deterministic tie key and empty typed output
remain independently authored obligations.

## Focused evidence and remaining acceptance

After repair, aggregate property/filter callers passed **22/22** JS
(`run-3yZ1Ch` / `focused-test-ebZvIC`). Fixture/profile Node tests passed
**15/15** (`run-VDMVPH` / `focused-test-DLcaGg`). Formatting and diff whitespace
passed. These are pre-integration observations.

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/aggregate_property_order_test.mbt \
  src/query_program/aggregate_filter_test.mbt \
  src/query_program/aggregate_filter_scope_test.mbt
node scripts/local-checks.mjs test node -- \
  scripts/aggregate-property-order-source-input.test.mjs \
  scripts/public-query-profiles.test.mjs
```

The existing normal and selected packed corpus shares **24 normal, 10 refusal
and 1 execution-failure cases per Embedded Local/HTTPS**. New cases cover the
receiver, qualified/quoted receiver, range collision and empty input. Existing
independent JSON controls, ordered contracts, assertions, predicates, parameter
values and ceilings are retained. Public exact-HEAD five-package execution is
pending at this evidence commit; focused compilation does not establish it.

The follow-up is stacked after the receiver-identity repair in #1022 so it
retains that repair and its generated current-contract pins. Move the base to
main only after that parent lands; do not merge into a dependency branch.
No new normative identity or pin is introduced by this static connection.
Broader computed order, full Core/Native/Wasm/Cloud and required CI remain
unverified. No manual CI rerun or merge.
