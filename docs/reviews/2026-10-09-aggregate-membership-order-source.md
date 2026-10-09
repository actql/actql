# Aggregate membership and interval ordering: source connection

This unit starts at `1646252bdb2f47ccb683c688b258b3ff472ea1a9`
(PR #1080, Boolean aggregate ordering). It extends the same ordinary
expression admission guard. The dependency is not claimed merged or reviewed.
Final target is main; preserve the parent dependency until its integration.

## Contract and fixed counterexample

Selected primary reference: [GoogleSQL operators at d82db99a](https://github.com/google/googlesql/blob/d82db99a923a46571f543a13899dc791a7b6f743/docs/operators.md).
The retained file `/private/tmp/actql-b-googlesql-operators-d82db99a.md` has
SHA-256 `70914979828c98ee5b8fb81036bc106605aa1c18560cd499febff1f1e4c626bc`.
Current [official documentation](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/operators)
was also inspected. BETWEEN evaluates its search value once; membership
preserves match-before-NULL and empty-set behavior; IS DISTINCT FROM has a
nonnullable Boolean result. This is not a live Google differential campaign.
The current common finite-number/type profile remains authoritative for the
selected inputs; no complete Google type-conformance claim is made.

```sql
SELECT STRING_AGG(name, '|' ORDER BY payload.score IN (20, NULL) NULLS LAST, id)
  AS names
FROM objects
```

Before repair, an independently authored complete Program with ordinary
`derive.in` and `group.string_agg` passed the common checker. Its source
counterpart failed with `UnsupportedAggregate` (0/1, `run-lgSFim`,
`focused-test-jEvIec`). This establishes a lowering gap, not a pre-repair
published Run failure.

The total-expression guard omitted BETWEEN, IN and IS DISTINCT FROM even
though the common expression lowerer already implements them. Connect those
predicates and total ARRAY operand trees to that guard, then preserve ordinary
lowering. Do not expand BETWEEN into duplicate comparisons, coerce membership
NULL to FALSE, turn a computed list into literal data, or invent key evidence.
Common admission still rejects unsupported computed/annotated membership
lists. Invalid comparison domains and missing parameter declarations remain
common checking obligations. Potentially failing arithmetic/casts/LIKE remain
outside this order-key hoisting profile; masked aggregate arguments retain
existing per-call demand semantics.

## Independent expectations

Complete JSON controls and authored source use the existing public acceptance
fixture, normal corpus and `--aggregate-property-order-only` cohort. There is
no separate evaluator, Host profile, capacity override or test-side Program
repair.

- Score values 20, duplicate 10, SQL NULL object and SQL NULL member distinguish
  membership with a NULL item (`a|b|b|c`) from membership without it
  (`b|b|a|c`). Duplicates are retained.
- IN UNNEST literal lists preserve NULL atoms and repeated entries. An empty
  list is an existing total set; no ordinal substitution is performed.
- BETWEEN and NOT BETWEEN produce opposite Boolean groups. IS NOT DISTINCT
  FROM 20 yields `b|b|c|a`; IS DISTINCT FROM NULL yields `c|a|b|b`.
- SET current and original range snapshots have distinct authored expected
  strings; typed parameter values and list holes retain declarations.
- A failing aggregate argument masked by WHERE FALSE remains unexecuted.
- JSON and source ARRAY controls use explicit ASSERT UNIQUE BY, sort and
  bounded take; expect `[2,1,3,4]`, with the existing nonnullable item contract.
- Operand type, removed range, unsafe bound and DISTINCT-key refusals retain
  exact public codes and must occur before admission/provider I/O.

## Verification so far

Pinned toolchains and bounded/nonzero-test wrappers:

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 300 -- --target js src/query_program/aggregate_membership_order_test.mbt src/query_program/aggregate_predicate_order_test.mbt src/query_program/in_unnest_literal_array_test.mbt src/query_program/distinct_aggregate_order_test.mbt
node scripts/local-checks.mjs test node --timeout-seconds 120 -- scripts/aggregate-conditional-order-source-input.test.mjs scripts/aggregate-signed-order-source-input.test.mjs scripts/aggregate-property-order-source-input.test.mjs
```

Pre-main-integration focused JS: 16/16 (`run-BDuJ0g`,
`focused-test-kn7s5w`). Earlier post-repair probes identified that a typed ARRAY
control is rejected by common admission; it was replaced by an unannotated
positive control and retained as a separate refusal obligation. The unsupported
INT64 test annotation was corrected to the already admitted FLOAT64 surface,
and its actual common checker refusal was fixed at that boundary. No product
contract or expected result was weakened. `run-GrsCBZ` was interrupted after an
edit script failed before writing its changes; it establishes no success.

Public execution, five-package identity, submitted-HEAD required CI and content
review remain unverified at this preparation stage. Full Core, Wasm/native,
proof/performance and the entire packed campaign are not local obligations for
this focused change. This unit does not close the entire Frontend.
