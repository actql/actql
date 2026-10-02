# Named SGA query syntax: independent parser boundary

This is an implementation checkpoint for the second unit of
[public language migration](../design/frontend-language-migration.md).
It does not establish public source execution, Graph consumer support or
completion of the migration. The old AQL/PROGRAM/STAGE and STEP/OP public
entry points remain withdrawn; machine JSON/YAML inputs remain supported.

## Implemented boundary

`query_syntax.parse_sga_call(text, limits, source_path?)` uses the existing
Unicode tokenizer, query parser and bounded work/node accounting. Its
`SgaCall` retains the logical operation name, typed argument syntax and
original byte range. It does not choose a physical backend, fetch an input,
admit a Program, issue compiler evidence or execute a provider.

The closed vocabulary is the adopted ActQL SGA vocabulary: reach, traverse,
shortest_path, components, degree, graph_bounds, match_nodes, match_edges,
normalize_graph, subgraph, graft_graph, union_graphs, subtract_graphs,
graphs_equal, graph_diff, apply_graph_delta, mean_graphs, node_rows and
edge_rows. These are ActQL logical operators, not a claim that ISO GQL
defines functions with these signatures.

Argument roles come from the existing logical contracts:

| Position | Syntactic role |
| --- | --- |
| reach/traverse `start.from` | Relation producer reference |
| shortest_path `source.from` / `target.from` | Relation producer reference |
| subgraph `nodes.from` | Relation producer reference |
| peer operations `with`, including mean_graphs lists | Explicit producer reference(s) |
| reach `start: "A"` | ID value, never a producer inferred from the String |
| apply_graph_delta `field: "delta"`, selector `id: "id"` | Column designation value, not a producer |

Bare/backtick producer names retain their naming distinction. String tokens
cannot name producers. Operation/selector vocabulary is folded separately
from object-valued data: a literal object with `Name` and `name` retains both
authored fields. Decoded String values retain CR and decomposed Unicode;
adjacent String chunks follow the existing lexical rules. Numeric tokens
retain exact spelling until ordinary numeric admission rather than being
rounded in this parser. Operation-specific types, required fields, numeric
ranges and Carrier cardinality remain common checker obligations.

Explicit mean_graphs lists contain only the listed producers. The parser
does not insert a current input, generate Results or order declarations, or
force an acquisition/materialization/task boundary.

## Remaining connection

The parser entry is not yet routed by `parse_query_script`, SDK or CLI.
Existing public source remains a typed refusal for these unconnected calls.
No new source input is claimed executable by this checkpoint.

The next Frontend connection must resolve DATA names to existing producers,
emit the existing operation bodies in the same Program, and use the adapted
common output Carrier/schema to continue either Graph or Relation processing.
It must reject unknown/forward references and duplicate input specification;
it must not use a second name resolver, reconstruct a legacy Graph or infer
new-model output identity/schema from historical simple-Graph fixtures.

At the fixed base `d144e25567313168558750fa17d02cc20e55dcf6`,
`graph_typing.check` still calls `require_legacy_profile` for normalize_graph,
degree, components and graph_bounds. `check_reach` has the same guard. These
guards reject the new Property Graph; parser success cannot remove them or
prove a common consumer is adapted. C's unified contract remains the
dependency for actual new-model execution. Snapshot/reload remains common
owner work, not an additional Frontend format.

## Validation scope

The six independently authored SGA parser tests cover argument roles, explicit
Graph lists, all adopted names, malformed/duplicate arguments, String-reference
rejection, exact decoded values/numeric spelling, limits and original source
positions. The entire query_syntax JS package passes 77/77. Public interface
generation inspects JS/Wasm/native consistently.

No Local/HTTP SGA Run, Result, provider call, capture or replay was executed by
these syntax tests. No common checker, provider, Host, snapshot owner, SDK or
CLI implementation changed. No public grammar/CID pin changed, because the
new parser component is not yet part of public script routing. When that
routing changes, its grammar, dependent pins and independent fixtures must
be coordinated with the source acceptance.

Reproduce the narrow syntax validation with the pinned repository toolchain:

```sh
moon test --target js -p actql/actql/query_syntax
moon info --target js,wasm,native -p actql/actql/query_syntax
```
