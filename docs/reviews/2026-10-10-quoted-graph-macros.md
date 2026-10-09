# Quoted names in the installed Graph macro namespace

Base: `584b3a6144d4a8053ca4a541ef042a6e17c674e9`.
This unit is independent of the statistical alias repair and does not depend
on another unmerged frontend branch.

## Existing meaning and reproduced gap

Query names are decoded by the syntax owner; installed function vocabulary is
ASCII case-insensitive and existing scalar/aggregate lookup does not treat
backticks as a different function namespace. Graph macros are closed ActQL
binding-role projections, not a new runtime Graph element type or a claim of
standard GQL function support.

The bare NODE_ID control and independently authored full Values/constructor/
match/filter/property/select Program checked and compared successfully.
Changing only the function spelling to backtick-quoted NODE_ID instead returned
`Expression(UnknownReference)`:

```aql
DATA g = PROPERTY GRAPH (
  NODE TABLES (objects AS N KEY (id) LABEL Person PROPERTIES (id, payload))
);
FROM GRAPH g |> MATCH WALK (a:Person)
  |> WHERE `NODE_ID`(`A`) IS NOT NULL AND a.payload.score > 10
  |> SELECT a.id AS id, a.payload.score AS score
```

Compiler pre-fix evidence: `run-38PUrf`, `focused-test-RCdTmv`, 0/1. The log
identifies quoted NODE_ID as the first failing variant after the bare control.
The earlier `run-EvMmHg` / `focused-test-ymNG9u` has the same refusal without
the function spelling in its message. Neither is public Run execution evidence.

`graph_macro_value` excluded every quoted function name before resolving its
decoded spelling. Remove that single exclusion. Keep the one-part namespace,
one variable argument, matching binding and admitted role/field requirements.
No alternate Graph representation, common checker, execution Owner, snapshot,
resource ceiling, grammar, schema pin or canonical law changes.

## Independent obligations and evidence

- A complete authored Program comparison covers bare, quoted, mixed-case and
  escaped NODE_ID names with the same identity predicate and nullable member.
- Private role-table tests verify that quoted NODE_ID, EDGE_SOURCE, EDGE_TARGET,
  EDGE_LABEL and PATH_LENGTH resolve to the existing identity/source/target/
  label/hop-count slots. Unknown names, wrong binding kinds, absent variables,
  one quoted dotted name and a two-part namespace remain unavailable. These
  helper tests are not public execution evidence for every edge macro.
- Existing normal Graph property acceptance gains an independent identity JSON
  control, three quoted NODE_ID variants and a typed empty result. A separate
  authored Graph/traverse JSON control and bare/quoted/escaped PATH_LENGTH
  sources expect two depth=1 rows from independently keyed parallel self-loops.
  The output does not deduplicate those occurrences or expose identity slots.
- Unknown, qualified-namespace, wrong-role, wrong-arity and expired-binding
  source cases remain preparation refusals. The existing public harness checks
  no new Run admission or source I/O, Result rows/description/types/column order,
  completed streams and same-request/Result-read reuse without re-execution.

Focused JS command:
`node scripts/local-checks.mjs test moon -- --target js
src/query_program/quoted_graph_macro_test.mbt
src/query_program/quoted_graph_macro_wbtest.mbt
src/query_program/graph_projection_property_test.mbt
src/query_program/keyed_graph_program_wbtest.mbt`: 13/13;
`run-OiQ4BJ`, `focused-test-puunR9`.

Focused Node command:
`node scripts/local-checks.mjs test node --
scripts/graph-member-source-input.test.mjs`: 5/5;
`run-mEU0Rt`, `focused-test-bF3Lr9`.

At this source commit, exact-HEAD normal five-package production and
`node scripts/test-packed-public-query.mjs --graph-projection-property-only`
are pending. Expected cohort: 22 successful cases and 11 preparation refusals
per Local/authenticated HTTPS transport. Their receipt, full source SHA and
tarball digests will be recorded in the PR body without changing the verified
source commit. No full Core, full packed campaign, Wasm/native execution,
hosted CI success or broader standard Graph conformance is claimed.
