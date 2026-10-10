# Connected Graph Relation operations as Pipe JOIN inputs

Date: 2026-10-10. Stacked on #1224 (traversal/JOIN), which depends on #1221
(Graph rows/JOIN). Main 5f9484cf2288cccbcefc3020a507cc04c3a2914e was normally
merged before this unit; integration base 738aa1fae3f6b0ae3929fbeba5c5a41a801fd811.
The only merge conflict was the packed fixture import list: both the inherited
Graph JOIN fixtures and main's retained-fixture encoder import were preserved.

## Counterexample and existing common contract

The independent complete JSON controls for degree, components, graph_bounds,
graphs_equal, graph_diff, match_nodes and match_edges all pass the ordinary
common checker. The corresponding complete source with a following Pipe JOIN
failed in syntax at the first degree case. Before repair: 1/2 tests passed,
_build/local-checks/attempts/run-XOzRZm and
_build/focused-evidence/focused-test-BkjV5v. This is parser/checker evidence,
not a public Run reproduction.

~~~aql
DATA n = SELECT 1 AS node_key, 7 AS p;
DATA r = SELECT 20 AS tag UNION ALL SELECT 10 AS tag;
DATA g = PROPERTY GRAPH (
  NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p))
  EDGE TABLES (n AS E KEY (node_key)
    SOURCE KEY (node_key) REFERENCES N
    DESTINATION KEY (node_key) REFERENCES N LABEL R PROPERTIES (p))
);
FROM g |> degree(direction: 'out')
  |> AS l |> CROSS JOIN r AS rr MAX_OUTPUT_ROWS 10
  |> SELECT l.degree AS value, rr.tag AS tag |> ORDER BY tag
~~~

Independent expected rows: [{"value":1,"tag":10},{"value":1,"tag":20}].
The keyed self-loop has one outward incidence. The right input is deliberately
in the opposite order. Output columns are value then tag, both non-NULL number.

## Repair and scope

The parser's JOIN prefix classifier and script Graph-to-Relation dispatcher
now use the same query_syntax.has_sga_relation_lowering classification.
It enumerates only already connected Relation outputs. False means that this
source profile has no connected Relation lowering; it is not a new assertion
that every other logical operation returns Graph.

Existing operation lowerers and the common checker retain responsibility for
arguments, input Carrier validity, identity, output fields, presence and NULL.
No new execution owner, backend choice, resource ceiling or common contract is
introduced. The selected public interface was regenerated with pinned
moon info --target js src/query_syntax; the only new signature is the helper.
The grammar/rules manifests are unchanged and their read-only vectors pass.

## Independent public obligations

scripts/fixtures/graph-relation-join-source-input.mjs registers 18 positives,
nine pre-admission refusals and one execution ceiling failure in normal packed
acceptance as well as the focused --graph-relation-join-only cohort:

- Six operations have independent complete JSON and text controls. graph_diff
  adds separate JSON and text controls with independently authored full Delta
  identities, preserving their different definition domains.
- Explicit operation arguments and JOIN ceiling 10, static definition selection,
  self-loop degree, component size, graph diagnostic count, equality, property
  values and complete JSON Delta content remain observable.
- Graph-returning normalization before degree, parameter bound zero, an empty
  property selection and WHERE/LIMIT exercise the existing Relation continuation.
- Wrong output fields, an old Graph range, invalid arguments and invalid JOIN
  ceiling refuse before Run admission/provider I/O. A valid ceiling of one
  instead rejects excessive execution output without a partial successful Result.
- Existing public acceptance verifies declared column order/types/nullability,
  same-request reattachment/retransmission, Result rereads and zero Source reads.

Main introduced a full-corpus registration inventory after the two parent
branches were authored. The existing data-only registeredPublicQueryInventory
enumerator regenerates registration hashes, not result expectations. Retain
the original source baseline and add this merge's registration baseline.
The three authored Graph/JOIN cohorts add 36 positives, 20 refusals and three
execution failures: 3050 total profile occurrences. Static count assertions
independently check that accounting. This is not full-corpus execution evidence.

## Focused evidence and remaining delivery

Pinned Node 22.22.0 / MoonBit 0.10.12+1634b282e, JS backend:

~~~sh
node scripts/local-checks.mjs test moon --timeout-seconds 120 -- --target js \
  src/query_program/graph_relation_join_input_test.mbt \
  src/query_program/graph_diagnostics_test.mbt \
  src/query_program/graph_rows_join_input_test.mbt \
  src/query_program/traversal_join_input_test.mbt \
  src/query_program/graph_equality_test.mbt \
  src/query_program/graph_delta_source_test.mbt \
  src/query_syntax/sga_call_test.mbt
node scripts/local-checks.mjs test node -- \
  scripts/graph-relation-join-source-input.test.mjs \
  scripts/graph-rows-join-source-input.test.mjs \
  scripts/traversal-join-source-input.test.mjs \
  scripts/public-query-profiles.test.mjs \
  scripts/compilation-manifests.test.mjs
~~~

Post-fix JS 35/35: run-OqoXud, focused-test-qC46BO.
Node 35/35: run-01VUF0, focused-test-D9ieKf.
Only changed MoonBit files were directly formatted; git diff --check passed.

At this document's commit, normal five-package production and selected packed
Local/HTTPS are pending. Exact source SHA, digests and original retained receipts
will be recorded in the PR after execution. Parent successes remain evidence
for their own SHAs, not this merged source. No full Core, all packed campaign,
Wasm/Native execution or CI success is claimed. Final merge destination is main;
retain the parent dependency until it reaches main.
