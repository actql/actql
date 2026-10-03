# Named SGA query syntax: independent unified-source checkpoint

This is an independent implementation checkpoint on B source
`1799232548c875212935b5e5cca6f9702fe9ea6d`, based on main
`0fd6332757176b88e8c4071e4a2cd0be3d6254e3`. Neither provisional C SHA
`321684933dce17afb0edc40f8877d2d7460c3da2` nor public
`125a186ae9396fbfc7865641922e8e8a4ffc87d9` is adopted. This is a checkpoint for the second unit of
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

## DATA/query connection and remaining common consumer work

The same token stream now parses named calls inside DATA and Pipe queries.
QueryOperation accessors copy nested arguments rather than expose the parser's
mutable arrays. DATA Graph aliases and normalize_graph prefixes retain the
existing Graph producer. Normalization emits one ordinary normalize_graph
step; it does not duplicate Values or add Stage/Result/materialization owners.
The following definition-selected MATCH consumes that step's output.

The whole normalized Program is compared with an independently authored
machine Program, including actual producer references, matching fields and
Result root. An inline prefix and a DATA alias share the same lowering.
The existing Graph name resolver is shared by declarations and MATCH.
Unknown references, extra normalize arguments, attempted Relation inputs and
unconnected output consumers are refused. Unconsumed Graph calls cannot be
ignored by ordinary relational compilation.

No new SGA source input is claimed executable by this checkpoint. Public
source preparation refuses constructor-dependent Graph queries with typed
UnsupportedGraph until the formal unified-owner handoff. No old checker
profile or normalize kernel is used as a substitute. Other
parsed named calls remain explicit UnsupportedGraph at lowering until their
adapted output Carrier/schema is connected. No unsupported shape is silently
given a historical simple-Graph type or executed through an old kernel.

Remaining Frontend connections must resolve DATA names to existing producers,
emit the existing operation bodies in the same Program, and use the adapted
common output Carrier/schema to continue either Graph or Relation processing.
It must reject unknown/forward references and duplicate input specification;
it must not use a second name resolver, reconstruct a legacy Graph or infer
new-model output identity/schema from historical simple-Graph fixtures.

The earlier `d144e25567313168558750fa17d02cc20e55dcf6` branch and its
C-specific checker tests remain historical evidence. This checkpoint ports
only B syntax, lowering and independently authored Programs. It does not
copy the old common Graph checker, representation or snapshot owner.
Snapshot/reload and adapted SGA output contracts remain common-owner work.

## Current validation

On the reconstructed source: query_syntax JS **79/79**, query_program JS
**150/150**, and public source preparation JS **11/11** passed. Four named
SGA lowering cases and six unified-dependency preparation cases passed on
each Wasm/native target. The updated current canonical Grammar Manifest case
passed **1/1 on each JS/Wasm/native**. Independent Node manifest/Values
preimage tests passed **7/7**, and the real Values Run-material owner test
passed **1/1 JS**. The official generated public API comparison passed on
all three targets. No full Core or Client job was run.

The first Wasm invocation used the abbreviated package name query_program,
which also selected its JS-only bridge and failed before any test execution.
The exact package name actql/actql/query_program then ran the four intended
SGA cases successfully; no target declarations or test exclusions changed.

The updated grammar preimage is
`sha256:4e911e389d7c72405b29e2ef2ee8051aa5eb397b67e5e6c2bfe6df7e4bf9d7cc`.
It was independently reconstructed from normative source/schema roles,
without reading compiler-generated pins. Only its dependent compiler and
Run identities change; the Values Unit and existing barrier stay unchanged.
The reconstructed source passed `npm run check:spec` once before commit,
including version, resource, metadata, contract, documentation and calendar
checks. Load averages sampled during it were 20.53/24.37/19.98; timing is
not a performance result. The record describes a working-tree verification,
not a second clean fixed-SHA full gate or Linux CI result.

The current grammar/profile is reconstructed independently from normative
files; historical values vectors retain their original preimages. There is
no packed public Graph execution, new-owner checker or snapshot evidence.

## Historical validation on the provisional dependency

The following records describe the original old-dependency checkpoint, not
this reconstructed branch or unified common-owner acceptance.

The six independently authored SGA parser tests cover argument roles, explicit
Graph lists, all adopted names, malformed/duplicate arguments, String-reference
rejection, exact decoded values/numeric spelling, limits and original source
positions. Two added composition/accessor tests bring the query_syntax JS
package to 79/79; four new Graph lowering/rejection tests pass 4/4 on JS.
The earlier syntax-only checkpoint had 77/77. The whole query_program JS package passed 154/154; the four new tests passed
again after strengthening the refusal assertion to the exact common
UnsupportedGraphProfile. Public interface generation and its official check
passed consistently across JS/Wasm/native. The affected query_program
package checks passed on all three targets.

No Local/HTTP SGA Run, Result, provider call, capture or replay was executed by
these syntax tests. No common checker, provider, Host, snapshot owner, SDK or
CLI implementation changed. Query EBNF and source rules now describe this
limited connection. Their Grammar Manifest and dependent compiler pins were
regenerated from source with compilation-manifests.mjs. The current grammar
body CID is sha256:ce9928ee2f46dd5d930ae6260b64a61f8a09aff1dea68e47b00a436e6762061b.
An independent sorted-JSON/Node crypto test reconstructs the normative
preimage; its literal expectations were independently calculated with Python
hashlib, not copied from compiler output. It and the existing manifest tests
passed 5/5 and run in check:contracts. Program version remains 0.1.

update-document-metadata.mjs updated the complete manifest import and its
normative document references. check-canonical-json.mjs regenerated only the
current manifest contract case; historical vectors retain their original
preimages and expected CIDs. That updated contract test passed once on each
of JS/Wasm/native. The first spec attempt detected stale normative imports;
the next detected the stale current contract fixture. Both were corrected
through their source generators. The final invocation passed check:spec,
strict Local resource completion, independently pinned execution authorization
vectors and metadata checks. Its final git diff --exit-code step detected the
intentional uncommitted implementation diff; this must be checked again after
committing, without claiming that invocation was a clean fixed-SHA job. The
specification checks themselves did not add a tracked change. Full Core,
Client, packed acceptance and Linux CI were not run for this checkpoint.

Reproduce the narrow syntax validation with the pinned repository toolchain:

```sh
moon test --target js -p actql/actql/query_syntax
moon info --target js,wasm,native -p actql/actql/query_syntax
```
