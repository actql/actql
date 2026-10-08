# Signed aggregate-local order keys

Inspected and normally merged main:
`70825a8350c2d80ee2813ea7609fb37e6b4980d6`.
Stacked dependency: #1026 at
`db5c7f14d446b00d1fa8faad6779d7ebf257dbed`, retaining #1023 and #1022.
Final destination is main after the parents land.

## Independent discrepancy

```sql
SELECT STRING_AGG(name, '|' ORDER BY -payload.score NULLS LAST, id) AS names
FROM objects
```

This parses but the aggregate order receiver guard rejects Unary AST nodes.
An independently authored complete Values Program derives the existing
`negate(property(score, field(payload)))` expression into a private order slot
and passes ordinary checking. Unary plus uses the existing double-negate
lowering. The actual pre-repair check passed **1/2**, with the source counterpart
failing compilation (`run-5IPj7f` / `focused-test-KTtQOc`). An earlier attempt
had a test helper signature error and is not discrepancy evidence.
No pre-repair public execution is claimed.

The selected GoogleSQL aggregate-call reference permits ordering expressions
and requires DISTINCT keys to denote the argument:
https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/aggregate-function-calls
The pinned analyzer checkout is
`d82db99a923a46571f543a13899dc791a7b6f743`. This is reference inspection,
not differential execution against a Google service.

## Minimal existing-contract connection

Recognize numeric unary signs in the existing static receiver chain. Preserve
the original AST and pass it to `append_with_properties`; never substitute a
signed expression with its underlying column. Existing parameter resolution,
input scope, common numeric/member/NULL checking, work limits, private slot
allocation and collection ceilings remain authoritative.

Numeric negation is type-preserving for the admitted finite number/decimal
contracts, and preserves SQL NULL. This does not admit arbitrary calls or binary
arithmetic for hoisting before aggregate demand. The masked-argument fixture
keeps a division-by-zero expression under WHERE FALSE and expects NULL, while
the existing demanded-argument failure remains an expected failed Run.
Broader computed aggregate ordering remains an unconnected profile rather than
a permanent language restriction. No runtime, checker, planner or Host changes.

The input has duplicate id=2, nullable objects/fields and a NULL argument.
Negative property order yields `a|b|b|c`; dropping the sign yields `b|b|a|c`.
Current and pre-SET snapshot receivers give different values. The ARRAY_AGG
fixture retains an explicit unique-id assertion, LIMIT and secondary id order;
negating a key does not create new uniqueness evidence.

## Main integration and independent identities

Merge `f086b789f455dd1aab630cd70454d65fd0e06786` retains both main's GROUP BY ALL /
BY NAME ON additions and the aggregate DISTINCT/order parent fixes. Existing
generators updated compilation manifests, document metadata, spec imports and
canonical fixtures. The signed connection itself changes no syntax contract.

The combined grammar CID is
`sha256:17b95025f2fe4b83389c467ea0b35fb5fcfb571a146ee862ddcc91fea10cb131`.
The independently authored Values Run preimage now yields
`sha256:bfeaee4389acbd2a5f74ff3b909fc1a1255abf4954b2a083ab2d4b8e2cc9ebf8`;
its Unit, Proof and ResultPlan identities are unchanged. Historical parent/main
vectors retain their original pins and the installed-dependency preimage.
No product-issued CID was copied as an expectation.

## Focused evidence

Final affected JS tests: **23/23**, `run-vs37OS` / `focused-test-qdjayw`.
Node fixture/profile/vector/manifest tests: **31/31**,
`run-fnBdX8` / `focused-test-LMO0Qq`. Changed-file formatting, diff whitespace
and read-only compilation-manifest validation passed. Integration generation
also verified the complete spec imports and canonical identities; it is not
backend execution evidence.

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/aggregate_signed_order_test.mbt \
  src/query_program/aggregate_property_order_test.mbt \
  src/query_program/aggregate_order_parameter_test.mbt \
  src/query_program/distinct_aggregate_order_test.mbt
node scripts/local-checks.mjs test node -- \
  scripts/aggregate-signed-order-source-input.test.mjs \
  scripts/aggregate-property-order-source-input.test.mjs \
  scripts/aggregate-order-parameter-source-input.test.mjs \
  scripts/public-query-profiles.test.mjs \
  scripts/client-values-run-materials-vector.test.mjs \
  scripts/compilation-manifests.test.mjs
```

## Public acceptance obligations

The existing normal and selected aggregate-property-order corpus includes
**51 normal, 27 refusal and one expected execution-failure case per Local/HTTPS**,
including **14 new normal and seven new refusal cases**. Sources and independent
JSON controls preserve the predicate, duplicates, NULLs, filter demand, keys,
argument types, column order and installed capacity. Refusals cover nonnumeric
operands, missing properties, unavailable ranges, mismatched DISTINCT keys,
numeric ordinals and unconnected binary expressions.

Normal clean-HEAD five-package production and the selected external consumer
are pending at this evidence commit. The PR body must record the actual result,
complete source SHA, manifest/digests and retained logs after execution. Existing
public checks include Named Result, Result.describe, private-column exclusion,
one Source session, resend/reread without reacquisition and admission/I/O counters
on preparation refusal. Focused checks alone do not establish these obligations.
Required CI, full Core/Native/Wasm/Cloud and broader Frontend completion remain
unverified. No manual CI rerun or merge.
