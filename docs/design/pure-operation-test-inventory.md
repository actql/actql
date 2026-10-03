# Pure-operation acceptance evidence inventory

This maps the 48-operation scope to existing operation tests, pipeline consumer
tests and machine-schema owners. It is an evidence index, not a conformance
certificate: file existence and a schema property do not prove semantic
coverage. Earlier evidence-transfer findings are retained in
[the historical audit](../reviews/pure-operation-audit.md), separately from this
navigation index and the current Program construction contract.

Paths below are repository-relative. A row can group operations sharing a test
suite; grouping does not waive operation-specific or overloaded-Carrier cases.

Current Graph support is classified only by the existing
[family coverage inventory](../reviews/2026-09-19-sga-veca-tea-local-coverage.json).
Blocked operations below point to typed refusal evidence, not successful
execution. The shared public Host test derives its cases from that inventory
and checks refusal before Run admission, acquisition I/O and dispatch. The
retired `graph` constructor is refused; its replacement `property_graph` has
its construction, resource and lifecycle evidence in that same inventory.

| Operations | Operation tests | Pipeline tests | Schema owner |
| --- | --- | --- | --- |
| values | src/relation_values/values_test.mbt | src/pipeline_typing/values_test.mbt | scripts/values-schema.mjs |
| except, intersect | src/relation_set/set_test.mbt | src/pipeline_typing/set_keys_test.mbt | scripts/set-schema.mjs |
| cross_join | src/relation_join/cross_test.mbt | src/pipeline_typing/cross_test.mbt | scripts/cross-join-schema.mjs |
| row_window, window_events | src/temporal_window/check_test.mbt | src/pipeline_typing/window_test.mbt | scripts/window-schema.mjs |
| window_group | src/relation_typing/group_test.mbt | src/pipeline_typing/window_test.mbt | scripts/window-schema.mjs |
| lag | src/relation_typing/lag_test.mbt | src/pipeline_typing/lag_order_test.mbt | scripts/window-schema.mjs |
| watermark_rows | src/relation_typing/watermark_test.mbt | src/pipeline_typing/row_operations_test.mbt | scripts/window-schema.mjs |
| watermark_events | src/event_typing/check_test.mbt | src/pipeline_typing/event_test.mbt | scripts/event-schema.mjs |
| session | src/event_typing/session_test.mbt | src/pipeline_typing/session_test.mbt | scripts/event-schema.mjs |
| dedupe_events | src/event_typing/dedupe_test.mbt | src/pipeline_typing/event_dedupe_test.mbt | scripts/event-schema.mjs |
| to_events | src/event_typing/bridge_test.mbt | src/pipeline_typing/event_keys_test.mbt | scripts/event-schema.mjs |
| time_series | src/time_series/check_test.mbt | src/pipeline_typing/time_series_test.mbt | scripts/event-schema.mjs |
| interval_join | src/relation_join/interval_test.mbt | src/pipeline_typing/interval_test.mbt | scripts/event-schema.mjs |
| asof_join | src/relation_join/asof_test.mbt | src/pipeline_typing/asof_output_keys_test.mbt | scripts/event-schema.mjs |
| sequence | src/relation_typing/sequence_test.mbt | src/pipeline_typing/sequence_keys_test.mbt | scripts/event-schema.mjs |
| calendar_bucket, calendar_series | src/calendar_typing/admission_test.mbt | src/pipeline_typing/calendar_test.mbt | scripts/event-schema.mjs |
| events, vectors | src/carrier_projection/projection_test.mbt | src/pipeline_typing/bridge_audit_test.mbt | scripts/carrier-projection-schema.mjs |
| node_rows, edge_rows | src/program_check/property_graph_unsupported_public_test.mbt | scripts/property-graph-public-host.test.mjs | scripts/graph-schema.mjs |
| graph | src/program_check/property_graph_public_test.mbt | scripts/property-graph-public-host.test.mjs | scripts/graph-schema.mjs |
| normalize_graph, components | src/program_check/property_graph_unsupported_public_test.mbt | scripts/property-graph-public-host.test.mjs | scripts/graph-schema.mjs |
| degree, graph_bounds | src/graph_typing/diagnostics_test.mbt | src/query_integration/property_graph_host_custody_wbtest.mbt | scripts/graph-schema.mjs |
| match_nodes, match_edges | src/graph_typing/match_test.mbt | src/pipeline_typing/graph_query_keys_test.mbt | scripts/graph-schema.mjs |
| traverse | src/graph_typing/traverse_test.mbt | src/pipeline_typing/graph_test.mbt | scripts/graph-schema.mjs |
| shortest_path | src/program_check/property_graph_unsupported_public_test.mbt | scripts/property-graph-public-host.test.mjs | scripts/graph-schema.mjs |
| reach | src/program_check/property_graph_unsupported_public_test.mbt | scripts/property-graph-public-host.test.mjs | scripts/graph-schema.mjs |
| subgraph | src/program_check/property_graph_unsupported_public_test.mbt | scripts/property-graph-public-host.test.mjs | scripts/graph-schema.mjs |
| graphs_equal | src/program_check/property_graph_unsupported_public_test.mbt | scripts/property-graph-public-host.test.mjs | scripts/graph-schema.mjs |
| graph_diff | src/program_check/property_graph_unsupported_public_test.mbt | scripts/property-graph-public-host.test.mjs | scripts/graph-schema.mjs |
| apply_graph_delta | src/program_check/property_graph_unsupported_public_test.mbt | scripts/property-graph-public-host.test.mjs | scripts/graph-schema.mjs |
| graft_graph, union_graphs, subtract_graphs | src/program_check/property_graph_unsupported_public_test.mbt | scripts/property-graph-public-host.test.mjs | scripts/graph-schema.mjs |
| mean_graphs | src/program_check/property_graph_unsupported_public_test.mbt | scripts/property-graph-public-host.test.mjs | scripts/graph-schema.mjs |
| to_vectors | src/vector_typing/bridge_test.mbt | src/pipeline_typing/vector_projection_keys_test.mbt | scripts/vector-schema.mjs |
| normalize_vectors, score_vectors | src/vector_typing/check_test.mbt | src/pipeline_typing/vector_test.mbt | scripts/vector-schema.mjs |
| nearest | src/vector_typing/nearest_pair_test.mbt | src/pipeline_typing/nearest_output_keys_test.mbt | scripts/vector-schema.mjs |
| pool_vectors | src/vector_typing/pool_relation_test.mbt | src/pipeline_typing/pool_test.mbt | scripts/vector-schema.mjs |
| merge_rankings | src/vector_typing/ranking_merge_test.mbt | src/pipeline_typing/ranking_output_keys_test.mbt | scripts/vector-schema.mjs |
| text_rank | src/vector_typing/text_rank_test.mbt | src/pipeline_typing/text_rank_test.mbt | scripts/vector-schema.mjs |

## Interpretation and remaining review

The inventory gate checks exact scope coverage without duplicate operations,
real test/schema-owner paths and the presence of each body in both embedded
Program schemas. It does not count occurrences of a word as a successful test.
Existing schema-specific gates still check the bodies and pins themselves.

Examples already explicit in the test suites include empty typed values,
unknown Carrier fields, repeated set/window inputs, nullable semantic roles,
mixed Relation/Vectors nearest inputs, and separate Relation/Vectors pooling
suites. These are navigation points for review, not a claim that every possible
combination has been covered. `pool_vectors_test.mbt` complements the Relation
pooling suite; `nearest_input_test.mbt` and `nearest_pair_test.mbt` distinguish
side admission from pair compatibility. The row-bridge matrix is recorded in
the open audit and covers all four input Carrier kinds.

Still required: review the assertions against each normative rule and overloaded
alternative, connect external evidence and unresolved static obligations to the
combined checker, and verify source/consumer completeness. The 48 inventory
entries, numerical law corpora and green package tests cannot replace those
checks or establish evaluator/Host/Linux conformance.
