# Graph query identity evidence

The normative owners are [evidence propagation](../spec/language.md#evidence-propagation)
and the individual [Graph operations](../spec/language.md#graph-operations).
`relation_evidence.graph_query_keys` derives conditional keys from an immutable
checked Graph query, not from a caller's choice of field names or a proof flag.

| Query | Retained candidate key |
| --- | --- |
| degree | `node` |
| components | `node_id` |
| graph_bounds | `(kind, node_id)`, with nullable node ID for whole-graph reports |
| match_nodes | Exposed semantic node identity |
| match_edges | Entire exposed semantic `(source, target, label)` tuple |
| reach | `node_id`, including the declared semantic name as an exact-copy alias |
| traverse, emit nodes | `(start_id, node_id)` |
| traverse, emit paths | No field key inferred from endpoints |
| shortest_path, each_pair | `(source_id, target_id)` |
| shortest_path, nearest_per_source | `source_id` |
| shortest_path, nearest_pair | `source_id`, since successful output has at most one row |

These follow the actual grouping/selection units. Graph nodes and normalized
edge tuples are unique; node traversal retains one minimum depth per start/node
pair; shortest selection retains one path per selected unit. Enumerated simple
paths can share endpoints and are deliberately excluded. Diagnostic reports
have distinct kinds and at most one degree report per node; thresholds neither
prove valid input bounds nor suppress their ordinary validation obligations.
No synthetic scalar path ID or serialized identity is introduced.

Only exposed complete tuples become keys. A missing edge-label role or omitted
identity component supplies no tuple evidence; unrelated properties named like
identity fields do not substitute for semantic roles. Unknown Graph identity
domains supply no key. Known contracts, including nullable label or diagnostic
node components, retain their types. This does not relax a consumer's separate
non-null, string-only or ordering requirements.

`GraphQueryResult` and `key_graph_query_producer` retain the exact checked query.
Match, reach, traversal and shortest checkers now retain their original input
Carrier instead of only derived output structure. The pipeline still retains
the query's actual operand edges and preceding operations. `ValidateKeyProducer`
does not disappear during aliasing: graph admission, membership, predicates,
canonical tie-breaking, profiles and capacity obligations remain attached to
the producer and pipeline. This is conditional static evidence, not evaluator
conformance or execution permission.

Exact-copy projection can keep multiple aliases for a component. Removing one
copy retains others; losing the last copy loses the whole key. Work and UTF-8
name bytes are charged cumulatively before witness construction. Indexed
lookups avoid copying or rescanning arbitrary output field arrays. Graph typing
remains below evidence in the dependency graph; it cannot depend back on its
consumer.

Tests cover all query families and shortest selection modes, both traversal
emissions, complete/incomplete edge identity, nullable labels, semantic reach
aliases, opaque input, exact budget boundaries, original input-handle retention
and Result publication after projection. The graph-row bridge remains its
separate checked producer; these rules do not infer keys for arbitrary external
rows or manufacture a key for a single-row JSON/Delta payload.
