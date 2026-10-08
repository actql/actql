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
refusal. At the implementation commit, public acceptance, package identities and
required CI were pending; focused success alone did not establish them.


## Completed fixed-source public acceptance

Source and normal producer: `ebb10c5c1ba3ae71a52db139d3aabecc21461ebd`.
The checkout and every recorded command were clean at this exact SHA.
The normal five-package producer retained prepack; independent SHA-256 checks
matched every manifest tarball. No adapter overlay or corrected Program was used.

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-aggregate-conditional-order-ebb10c5c1-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-aggregate-conditional-order-ebb10c5c1-pack \
ACTQL_TEST_NPM_CACHE=/private/tmp/actql-b-aggregate-conditional-order-ebb10c5c1-pack/npm-cache \
node scripts/test-packed-public-query.mjs --aggregate-property-order-only
```

Both Embedded Local and real HTTPS completed **64 normal, 32 preparation
refusal and one expected execution-failure case**, including the new **13 normal
and five refusal cases**. All 64 normal cases and the demanded-argument failure
are individually logged per protocol. Eight refusals have individual log lines
(the new implementation-limit refusals are among these); the remaining refusals
use the retained unlogged rejection loop. The corpus cardinality and complete
consumer success establish the 32 total; this is not a claim of 32 refusal lines.
Rows, Result.describe type/nullability/column order, private-column exclusion,
Source acquisition count and unchanged-request replay/reread checks remained
active. Preparation refusals checked admission and Source-I/O counters.

Evidence:

- Wrapper: `run-lexsFX`, terminal success with all three steps complete and locks released.
- Receipt: `worktrees/.codex-scratch/public-query-evidence-AJoW0E`, ten complete
  commands with exit/verification zero, clean matching source, no evidence errors.
- Independent audit: `/private/tmp/actql-b-aggregate-conditional-order-ebb10c5c1-acceptance-audit-20261009.json`.
- Wrapper/log: `/private/tmp/actql-b-aggregate-conditional-order-ebb10c5c1-packed-20261009.mjs`
  and the corresponding `.stdout.log`.
- The owned fresh installation was removed by the successful evidence recorder;
  receipt/logs and the immutable five tarballs remain.

| Package | SHA-256 |
|---|---|
| client-wire | `18762bb0bf434d939ff153d485e2aed28f0fa3c77c9d1e82eee4983765947905` |
| sdk | `5e28c1fabbf8acbb5a00ea2d77a8ce8e3b5aefc04ed849d767b25ac477e29acf` |
| run-host-core | `41b5d6e6ecdb0ce8efc311766524225d9bb46f0fef3d21506194635c18c20d7f` |
| local-node | `d591774976f326e7cf0b5efb2368372fcc3a3545f0f236dd76110ab6087d277d` |
| node | `2989926be6f87295d48551e3c83e64dd6fb26f7b943e4004ad69176e19b98cda` |

The exact-source workflow lookup returned no runs at the observation time;
there is no CI success or run URL to report. No manual rerun or merge occurred.
This evidence-only follow-up changes no compiler, fixture, package, contract or
consumer input from the tested source; its commit SHA is still reported
separately rather than relabelling the producer's packages.
