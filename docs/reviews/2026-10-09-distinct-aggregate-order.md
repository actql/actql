# DISTINCT collection aggregate ordering

Inspected main: `210e51e8986ca0aef427e4a4fb3259b749466037`.
This is a source-profile validation repair, not a new aggregate executor or a
change to machine Program aggregate semantics.

## Selected rule and independent counterexample

```sql
SELECT ARRAY_AGG(DISTINCT x IGNORE NULLS ORDER BY y) AS items FROM pair
```

The existing Frontend emitted a Program for this source. The selected
[GoogleSQL aggregate-call reference](https://docs.cloud.google.com/bigquery/docs/reference/standard-sql/aggregate-function-calls)
requires DISTINCT collection ordering to use the aggregate argument.
Pinned checkout `d82db99a923a46571f543a13899dc791a7b6f743` corroborates this in
`googlesql/analyzer/resolver_expr.cc` and the independently authored
`order_by_in_aggregate.test` refusal examples for ordinary, qualified and
property references. No live Google service differential execution is claimed.

The red test failed because this query compiled instead of returning the
existing `UnsupportedAggregate`. This is a lowering observation, not a claim
that the old public runtime completed with an incorrect row.

## Minimal repair

`lower_aggregate_resolved` validates every authored order key of DISTINCT
ARRAY_AGG and STRING_AGG against the argument. The comparison uses the same
input resolver and existing `order_reference_identity` as ordinary property
lowering and ORDER reference reuse. It includes physical receiver identity and
the remaining case-insensitive property path. It does not compare the newly
allocated private ORDER slot with the argument or use a SELECT sibling alias.

Qualified/unqualified references, decoded backticks, grouping parentheses and
static `(payload).name` access can denote the same value. Current Pipe columns
and old range snapshots after SET cannot be substituted for each other.
No DISTINCT, order key, input predicate, parameter, collection limit or key
proof is removed. No input-wide DISTINCT is introduced by this repair.
Non-DISTINCT ordering by another column retains its existing behavior.

The common checker still owns argument types, nullable properties, collection
capacity and required order/key evidence. Computed aggregate-local ORDER calls
remain a separate coverage gap: an exploratory positive REPLACE-order case
hit the existing unsupported-order boundary and was not weakened into execution
evidence. Static ARRAY property cases prove lowering, not successful publication
of nullable-key collections.

## Independent expectations and focused evidence

`distinct_aggregate_order_test.mbt` includes a complete manually authored Values
Program for STRING_AGG, checks both expected and generated Programs normally,
and tests distinct slots, qualification, property receivers and old snapshots.
The public fixture contains a separate independently authored Source JSON
control, rows and complete ordered column contracts. Expected results are not
generated from a compiler or evaluator.

- Initial red: 0/1, `run-PxrUwS` / `focused-test-og2qqo`.
- Intermediate: 23/24; the only failure was the unsupported computed-order
  exploratory case, `run-IcfM1t` / `focused-test-fyQau0`.
- A helper compilation attempt failed before discovery; `run-Mdapi7` /
  `focused-test-VmoERF` is retained and is not test success.
- Corrected selection: 24/24, `run-3Xg6XZ` / `focused-test-T1TQyN`.
- Final JS: 25/25, `run-Wd3faQ` / `focused-test-bcC9sG`, including affected
  aggregate order/filter callers and the independently updated Values Run.
- Node: 21/21, `run-AQeFvs` / `focused-test-UvMONq`; after adding the keyed
  ARRAY public expectation, its two fixture/registration tests passed again,
  `run-3FmdUf` / `focused-test-SYwuYf`.
- Formatting, diff whitespace, read-only compilation/spec-family checks and
  380 canonical identities passed. Conformance remains false.

Commands use the repository's pinned toolchain and bounded nonzero-test wrapper:

```sh
node scripts/local-checks.mjs test moon -- --target js \
  src/query_program/distinct_aggregate_order_test.mbt \
  src/query_program/aggregate_property_order_test.mbt \
  src/query_program/aggregate_filter_test.mbt \
  src/query_program/aggregate_filter_scope_test.mbt \
  src/run_publication_host/client_values_run_materials_wbtest.mbt
node scripts/local-checks.mjs test node -- \
  scripts/distinct-aggregate-order-source-input.test.mjs \
  scripts/public-query-profiles.test.mjs \
  scripts/client-values-run-materials-vector.test.mjs \
  scripts/compilation-manifests.test.mjs
```

## Identity and public execution obligations

Existing generators bind the normative clarification, imports and manifest.
Grammar CID: `sha256:f36b20c837ff42642c5ccb147fc236c2c04d99e5dfa08cc63370a9f230d98ece`.
The independently reconstructed fixed Values Run becomes
`sha256:6aa682a0996249db7e4925fe71838dd078b242dd30efd193d34b35faa22c5ff4`.
The complete predecessor grammar/Run vector remains. Unit, ResultPlan and
barrier semantics are unchanged; saved Runs are not rebound to the new grammar.

The normal packed corpus and `--distinct-aggregate-order-only` share ten normal
and six refusal cases per Embedded Local/HTTPS. Required observations include
Named Result rows, column order/types/nullability, Result.describe, acquisition
counts, same-request resend, repeated reads and zero admission/provider I/O
on refusals. Empty STRING_AGG remains typed NULL; ordinary concatenation retains
repeated values; the keyed ARRAY retains its explicit assertion and input bound.

At this evidence commit, exact-HEAD normal five-package production and public
execution are pending. Record their actual revision/digests/results separately
in the PR; focused success does not establish public execution or required CI.
Full Core, Native/Wasm, Cloud, broader computed order and nullable ARRAY
publication are not established by this unit. No manual CI rerun or merge.

## Initial packed execution and fixture correction

Normal five-package production for `4d66f3ddf8dc398be8df5b2c79bfb4f0ad0b88e0`
completed and independent digest verification passed. The packed consumer
`run-zlTiTr` / `public-query-evidence-C59fdC` passed the first nine normal Local
cases, including the independent JSON control and keyed ARRAY, then stopped
before the static-property case was admitted: `ClientParametersInvalid`.
HTTPS and the refusal cohort were not reached; this is not complete acceptance.

The static-property fixture incorrectly put general string value evidence
`max_utf8_bytes` in a parameter declaration. `value_contract/parameters.mbt`
defines closed parameter syntax: string declarations permit `format`, not
general relation string bounds. Remove that unsupported declaration member;
keep the same parameter value, nullable object/field, expected row and aggregate
limit. A fixed declaration expectation failed 1/2 before the correction
(`run-iaAUcA` / `focused-test-dzuquM`) and passed 2/2 afterward
(`run-y72RWf` / `focused-test-5tyNlV`). The normal checker is not loosened.

The failed run's logs, receipts, package digest manifest and five tarballs
remain. Its re-downloadable npm content cache was removed separately; the
cleanup does not erase failure evidence. New integrated-HEAD public execution
will be recorded separately rather than relabeling these nine successes.
