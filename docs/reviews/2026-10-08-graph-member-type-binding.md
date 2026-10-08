# Graph member binding through common pipeline types

Date: 2026-10-08. B owns the Frontend connection. This is a bounded delivery
unit within the broader source-to-common-Program objective, which remains open.

## Counterexample and independent Program

```aql
DATA g = PROPERTY GRAPH (
  NODE TABLES (objects AS N KEY (id) LABEL Person PROPERTIES (id, payload))
);
FROM GRAPH g |> MATCH WALK (a:Person)
|> SELECT a.id AS id, a.payload.SCORE AS score
```

`payload` is a nullable closed object declaring nullable numeric `score`.
The existing handwritten full machine Program in
`src/query_program/graph_projection_property_test.mbt` passes ordinary checking.
Before the change, the member pass lost Carrier information at the constructor
and MATCH. It left `SCORE` unchanged, producing a different Program from the
independent exact-member control. Projecting `payload AS kept` and then reading
`kept.SCORE` has the same defect. No row value or expected order is changed.

`graph_member_test.mbt` compares the source with that independent complete
Program, including quoted mixed-case names. The projected-receiver expectation
inserts independently specified SELECT/derive/select steps into the handwritten
fixture, never into compiler output. Ordinary checking remains required.

## Common Owner connection

For a closed stage, retain the already-lowered prefix through Graph construction
and operations with a Graph input. Copy that prefix with prior member bindings
and run `pipeline_typing.check_carriers`. Its actual output supplies the next
member environment. This preserves constructor producer definitions, domain,
keys, labels and conditional property contracts through the existing Owner.
Frontend code does not manufacture a Graph, domain, property schema, uniqueness
witness or execution path. Final checking and runtime admission remain separate.

Each prefix copy charges its retained nodes; successful common checking charges
its reported work. A semantic refusal retains the remaining allowance and stops
subsequent probes. Exhaustion remains a typed Frontend WorkLimit. Prefix checking
is deliberately bounded even though repeated Graph transitions can revisit an
earlier prefix. No larger allowance or weaker common limit is introduced.

Stages with external inputs are not probed as closed stages. A schema attachment
alone is insufficient to issue their Graph definition domain. Completing those
facts requires the original `SourceViewInput`/`ProducedInput` owner and its
retained declaration/producer. The ordinary lowerer and checker remain in place;
this is missing Frontend metadata coverage, not a new language restriction or
permission to invent a domain. INFER/task-environment type propagation and the
genuine typed NEAREST Source installation are also separate unfinished work.

## Focused verification and current wire

- Pre-fix `run-zY4HCL`, `focused-test-49SqD3`: 0/2 Graph member tests. The exact
  independent Program/control checked; uppercase member comparisons failed.
- The same guarded invocation passed read-only
  `generate-client-publication-wire.mjs`, `generate-client-host-wire.mjs`, and a
  direct import of the current `packages/client-wire/index.mjs`.
  `publication.generated.js` is current registered-schema output, not a legacy
  fallback. These checks do not reproduce an unspecified earlier startup failure.
- `run-wNt8Gi`, `focused-test-IKwBNr`: 16/16 JS, including the existing Graph
  projection caller and member probe cases. The precedence warning was then fixed.
- `run-soGnGE`: 12/12 JS (`graph_member_test.mbt`,
  `member_probe_budget_wbtest.mbt`), 3/3 Node
  (`scripts/graph-member-source-input.test.mjs`), and scoped `moon info` success.
  No public-interface change. These are working-change checks over
  `a6014b5ed15ac40d029fa4459ab5478f869a31c3`, not clean-HEAD execution or CI.
- Selected formatting and `git diff --check` passed. No full Core, cross-target,
  proof/performance or full packed campaign ran.

## Public acceptance obligations

The normal `graph-projection-property-source-input.mjs` inventory now has 13
positives and 6 preparation refusals. Existing independent JSON control,
nullable receiver/member, empty result, key/label, projected scope and invalid
receiver cases remain. Five folded-member positives and an uppercase missing
member refusal use the same consumer/profile as the existing cases.

Required public evidence is normal clean-HEAD five-package packing and the
existing `test-packed-public-query.mjs --graph-projection-property-only` consumer.
Compare Named Result rows, complete Result.describe contracts, column order,
stream completion, retries and refusal counters through Local and HTTPS. Expected
rows are IDs 1,2,3,4 with scores 20,10,NULL,NULL; the null-filter case retains 3,4
and the empty case retains its schema. No internal column may appear publicly.
Until that consumer completes, these are prepared obligations, not execution
evidence. The parent NEAREST change and full Frontend objective remain open.
