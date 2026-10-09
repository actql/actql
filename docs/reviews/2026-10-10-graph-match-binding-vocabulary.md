# Typed Graph match binding roles at the public text boundary

Base: #1186 `e74a3fe5f4c3bb98677b1ff2ce9c5438bb106ec3`, stacked on #1184,
on main `040eed2b1a11a3d1f7bae81b68d956d1017fac05`. Both parents must reach
main before retargeting. The separate QUALIFY execution-capacity handoff is
not a dependency.

## Existing contract and reproduced gap

The named logical SGA surface already uses case-insensitive operation
vocabulary with argument roles from existing contracts. Graph property match
in `docs/spec/language.md` defines bindings as a closed typed role map:
identity for nodes; identity/source/target for edges. Their values are
caller-selected field names, not vocabulary or ordinary properties. The common
Graph match checker owns definition/label scope, binding collisions, typed
identity, predicate/projection contracts and resource evidence.

Root BINDINGS folded, but its role fields did not. For example:

```aql
DATA n = SELECT 1 AS node_key, 7 AS p;
DATA g = PROPERTY GRAPH (
  NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))
);
FROM g
  |> MATCH_NODES(DEFINITION: 'N', BINDINGS: {IDENTITY: 'Element'},
                 WHERE: {literal: true}, FIELDS: ['Element', 'p'])
  |> SELECT Element, p
```

A hand-authored complete ordinary Program, with bindings.identity = Element,
checks successfully. Source lowered bindings.IDENTITY instead. Edge SOURCE
and TARGET had the same discrepancy; mixed-case role duplicates escaped
parser rejection. The pre-fix selected JS run passed 1/5 and failed four
counterexamples: guard run-qdww1G; focused-test-vARQn1. The unrelated literal
Identity/identity keys and decoded decomposed Unicode/CR were already preserved.
Command: `node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_syntax/graph_match_binding_vocabulary_test.mbt src/query_program/graph_match_binding_vocabulary_test.mbt`.

## Minimal repair and independent obligations

Use the existing parser role table at match_nodes/match_edges.bindings only.
Keep output field-name Strings unchanged, and do not fold where expressions
or nested literal data. Unknown/forbidden roles and output collisions reach
the existing common checker. No Graph contract/identity, checker, Owner,
resource ceiling, grammar production or pin changes.

- Exact parser argument and duplicate Syntax expectations; distinct literal
  Identity/identity keys and raw string values.
- Complete independently authored node Program, with uppercase/backtick role
  source variants; exact edge role body and field-order expectations; ordinary
  checker plus existing match-to-traverse integration callers.
- Public independently authored node/edge JSON controls bind identity and
  endpoints, then use ordinary is_null expressions and existing Relation-based Subgraph
  selectors. No
  product-computed opaque IDs or domains supply expectations.
- Source with uppercase node roles and quoted edge roles expects all three
  nullable-property nodes with bound=true, and both independently keyed
  parallel edges with all three identity/endpoint bindings present. Separate
  Source and Target selectors expect node 1/p=20 and node 2/p=10, respectively,
  despite two parallel-edge occurrences. Ignoring or confusing the
  roles cannot pass these observations.
- Quoted node role with an empty predicate result retains full declared
  column contracts/order. Typed identity values need not be exposed as a new
  user wire format to observe their common expression behavior.
- Four new refusals require ClientProgramInvalidInput: folded role duplicates,
  a source role forbidden on nodes, and colliding edge output names. Refusal
  checks preserve zero new Run admission/Source I/O.
- Additions use existing normal and narrow Graph-match public consumers, with
  Named Result rows, Result.describe types/nullability/order, complete streams,
  result rereading and same-request replay checks.

The old empty-fields fixture now explicitly requires its established
ClientProgramImplementationLimit. The unchanged lowerer and exact
`graph_match_rows_test.mbt` assertion establish UnsupportedGraph for empty
fields, and common client_check projects implementation_limit. No product
mapping, general allowlist, input, expected rows or limit is changed.

## Focused verification

Pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e, bounded/nonzero wrappers.
After repair, affected parser and callers: 23/23; guard run-tfNrr7;
focused-test-vMxhm8. Command:
`node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_syntax/graph_match_binding_vocabulary_test.mbt src/query_syntax/sga_call_test.mbt src/query_syntax/graph_merge_vocabulary_test.mbt src/query_program/graph_match_binding_vocabulary_test.mbt src/query_program/graph_match_rows_test.mbt src/query_program/graph_match_paths_integration_test.mbt`.
Evidence directories are `_build/local-checks/attempts` and
`_build/focused-evidence` in this checkout.

## Capability inspection and remaining boundaries

The selected main still does not have executable common graft_graph or
mean_graphs consumers. mean.mbt explicitly checks authored options only;
its vocabulary/options registration is not an executable operation. Existing
text refusal remains a support limit, not a permanent language restriction.
Do not add a frontend executor or treat those entries as publicly executed.
Existing named match and node/edge row transitions are already connected and
are retained; this repair changes only the discovered binding-role mismatch.

At this initial focused-check checkpoint, pristine packed execution was not
yet established. The completed fixed-source public evidence is recorded below.
Full Core, Wasm/native and submitted-HEAD CI remain unestablished. No merge or
manual CI rerun.

## Additional independent controls before packing

Initial repair/caller coverage remains 23/23 above. Adding complete public
controls first exposed two unsupported observations, before any package build:
- General is_distinct_from over the current typed Graph identities fails
  Expression(TypeMismatch("key-comparable operands")); guard run-eUihxb /
  focused-test-qRDDzo (23/24). `expression_typing/signatures.mbt` requires
  common key_comparable contracts. This is not a Frontend lowering defect.
  Original independent probe retained at
  `/private/tmp/actql-b-graph-match-binding-key-comparison-e74a3fe5f.json`.
- After switching to the existing selector contract, node_rows over this
  definition collided on node_key, intentionally exposed both as key and
  ordinary property. Guard run-HJUCTu / focused-test-lcv1t0 (23/24).
  The endpoint control now uses explicit match_nodes fields after Subgraph;
  constructor/property meaning and expected p/node_key values are unchanged.

No common comparator, collision rule or execution Owner was changed. Identity
existence is observed with is_null; endpoint correspondence is observed by
passing each checked binding to the existing Subgraph selector, followed by
an explicit property match. This preserves the obligation to distinguish the
endpoints rather than relying only on non-NULL handles. The four complete
independent JSON controls and both compiled role Programs now pass the normal
checker: 3/3, guard run-lJZMRP / focused-test-uRtHdR.
Command: `node scripts/local-checks.mjs test moon --timeout-seconds 180 -- --target js src/query_program/graph_match_binding_vocabulary_test.mbt`.

Final targeted Node fixture/corpus checks: 4/4; guard run-guK8O8;
focused-test-pfw6vl. Command:
`node scripts/local-checks.mjs test node -- scripts/graph-match-binding-vocabulary.test.mjs`.
Initial fixture check was 3/3 (run-suduii / focused-test-BNxDCE), before adding
the stronger endpoint-selector obligation. Changed-file moonfmt and
git diff --check passed.

## Initial clean packed run and second existing refusal-category correction

Product/fixture SHA: `bae348a5c769ead1f6290279877e6f171ad4dd84`.
Normal five-package production and independent digest verification completed,
guard run-To3Pmz. Original receipt:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-6K8x7O`.
All 19 Local positives passed, including the nine new source/JSON binding and
endpoint controls, before refusal graph-match-invalid-relation-is-not-graph
stopped the run. Its default code list excluded the established
ClientProgramImplementationLimit. Later refusals and HTTPS were not reached.

The unchanged compile_query_script guard and exact
`graph_match_rows_test.mbt` assertion already reject match_nodes applied to a
Relation with UnsupportedGraph. This old fixture now requires the same common
implementation_limit diagnostic explicitly, alongside empty-fields. No product
mapping, general allowlist, source, expected row or limit changes. The failed
original receipt/logs remain; its private installation was automatically
removed after preserving evidence.

The refusal-category correction passes the targeted Node fixture check: 4/4,
guard run-1FR96v / focused-test-BHIf83. Command:
`node scripts/local-checks.mjs test node -- scripts/graph-match-binding-vocabulary.test.mjs`.
This verifies fixture registration and precise categories, not the remaining
public refusal cohort or HTTPS execution.

## Complete pristine Local/HTTPS acceptance

Clean product/fixture source: `0192fd6b8f3aa40653700fd74ae080a4b656c69c`.
Normal five-package producer, independent digest verification and existing
`--graph-match-only` consumer completed under guard run-Gknlfm. Reproduction:

```sh
node scripts/packed-client-packages.mjs /private/tmp/actql-b-graph-match-binding-vocabulary-0192fd6b8-pack
ACTQL_PACKED_CLIENT_PACKAGES=/private/tmp/actql-b-graph-match-binding-vocabulary-0192fd6b8-pack node scripts/test-packed-public-query.mjs --graph-match-only
```

Use the pinned Node/MoonBit tools and existing serialized local-check guard;
the executed wrapper was
`/private/tmp/actql-b-graph-match-binding-vocabulary-packed.mjs`.

Local and HTTPS each completed **19 positives and 18 refusals**, with no omitted
case. Nine new positives include four independently authored JSON controls,
case/quoted role source cases, empty typed output and two endpoint-selector
counterexamples. Four new refusals require ClientProgramInvalidInput; two old
implementation-limit cases require their exact established category. The other
12 refusals retain their existing typed input-category checks. All refusals
require zero new Run admission/Source I/O; all positives retain rows, full
Result.describe column types/nullability/order, complete streams, attached
reads, same-request Run identity and no reacquisition on replay.

Original receipt/logs:
`/Users/t14i/workspace/20260822/worktrees/.codex-scratch/public-query-evidence-oVrLR3`.
Its summary is passed/complete with the clean source above, all 10 commands
complete at exit 0, no signal and no evidence errors. The private installation
was removed and its artifacts directory is absent. Guard evidence is
`_build/local-checks/attempts/run-Gknlfm`. The earlier failed pack/receipt remains
a separate observation; it is not rewritten as successful.

All five source-bound tarball SHA-256 values were independently recomputed and
matched both producer manifest and consuming receipt:

| Package | SHA-256 |
|---|---|
| client-wire | ca7aaf03f3f1d78aff24c42a4ebe94ae2136ce29ba3fdf8ed81478e359e3df60 |
| sdk | 64eca760cdce9f0da1ea53542ede457ec9f5c80603d9b13721077d90c7b91c1e |
| run-host-core | f556604d2d56a7bdd76865289c621a4f69ec766af78e03d942f81666b1acfb54 |
| local-node | 50168f05edb08335065839e8ce1b21aaa940b71d1ba3a0fe4344840d65cb6aaf |
| node | a77756e97078c7df0ea0a318e5ccd74bd7aee2891caa148da2688f9c3eb2d9eb |

The final submitted commit only records this evidence; pristine packed execution
belongs to 0192fd6b8, not an unexecuted later SHA. Parent #1186 remains open and
Draft; preserve its dependency and final main target. Full Core, Wasm/native,
complete unrelated packed campaigns and exact submitted-HEAD CI are unverified.
This closes this binding-vocabulary implementation/acceptance unit, not the
entire Frontend goal or the separate common capacity/consumer boundaries.
