# Graph subtraction public source connection

## Existing contract and observed gap

Integration baseline: `a48ba65cd80395a67cdad7d7c92e7d36e9aa1ec2`, a normal
merge of Graph union source HEAD `00ce5b40e7e1cd7c32acc277acab2110505bb843`
and main `c558da09dff69e1d84fed3741b86ca228b3a03a9`.
The one packaging conflict retains the existing export allowlist rewrite for
arbitrary adapter depth, including main's newly fixed nested SDK import and
unknown-import rejection. The actual nested adapter regression is retained.
Main's public check-context projection is taken unchanged.

The common `graph_typing/subtraction.mbt` and managed Graph provider already
implement binary `subtract_graphs`; the public named-call parser recognizes
its producer argument. Script lowering omits it. The pre-repair test accepts
an independently authored complete expected Program through the normal checker,
then fails compiling the equivalent source (`run-Ljfpj3`, 0/1).

The existing structural-graph normative section separates entity removal from
property strategies. Equal shared entities with no nonempty map for their kind
are removed. An explicit strategy, including `exact_equal`, retains the
transformed entity. A zero or unchanged property is not deletion. Node/edge
maps are independent; edges with a removed endpoint are then removed by the
common induced-closure rule. Conflicting unspecified values and actual NULL
numeric operands fail atomically. This PR connects that contract, not a new
graph subtraction interpretation.

## Frontend repair

The existing union argument-lowering module is named
`graph_composition_program.mbt` and shared by the two structural operations.
It retains the authored operation name, original expression origin, one left
producer and explicit peers/policies. Only union accepts nonempty peer lists;
subtraction requires a scalar Graph producer. Existing DATA name resolution is
reused; STRING, Relation, unknown and forward references do not acquire a Graph
or select another source. Both Graph-preserving DATA and direct rows pipelines
call the same module.

No common checker, algorithm, capacity, snapshot, identity, cancellation,
storage or publication owner changes. No extra source reads, sort, legacy
conversion, default merge policy or Frontend evaluator. Actual schema,
presence, nullability and compatibility remain common-checker decisions.
CTE, Source predicate, assert and Effect code are unchanged.

## Independent evidence

The complete simple Program oracle is authored independently and compared in
full after normal checker acceptance. Public constructor contracts are reused
from the independent union fixture, not generated from product lowering.
The independent JSON controls use both Named Results from the same Graph.
Source cases are complete one-terminal-query submissions; they include:

- Self subtraction without policies: empty typed nodes and edges.
- Explicit node `exact_equal`: node remains; equal edges with no policy disappear.
- Explicit edge `exact_equal`: cannot resurrect nodes removed by the node rule.
- Quoted Graph peer and numeric policies: node 14, parallel edges 4/10 with
  their original composite keys and labels.
- A node-1 subgraph removed from nodes 1/2: node 2 (property 9) and its self-loop
  (edge 10, property 2) remain. Edge 11 from node 1 to 2 disappears through
  endpoint closure despite being absent from the peer subgraph.
- Zero property with an explicit sum remains a value; nullable empty Results
  keep their declared nullable schema. NULL arithmetic and unspecified conflicts
  fail rather than publishing partial results.

The ordinary packed corpus includes 13 normal cases, 10 preparation refusals,
and 2 execution failures per transport. `--graph-subtraction-only` selects
these unchanged inputs in the existing public driver and default Host profile.
Expected rows, recursive types, column order, multiplicity and zero acquisition
counts are independently authored. Existing Result.describe, same-request Run
identity, attach/reread and admission/provider-I/O assertions are preserved.
Frontend refusal cases assert their specific public error codes.

- Focused JS: 21/21; Node: 15/15 (`run-17rbRb`), including unchanged union,
  Subgraph, source routing, fixed Run vectors and nested import regression.
- The preceding 10/11 attempt (`run-DCgoaV`) had a test comparing JSON object
  member order in a substring; separate reference/policy assertions fixed that
  fixture. The failure is retained, not counted as success.
- The submitted PR body records the actual fixed SHA, pack manifest/digests,
  receipt and Local/HTTPS outcomes. Syntax/checker success is not execution
  evidence, and public acceptance remains unverified until that receipt passes.

Helpers and logs are retained under
`review-artifacts/b-graph-subtraction-2026-10-06/` in the author worktree.
Full Core, Wasm/native, proof, performance and Cloud suites are not run locally.

## Identity and delivery

The existing query grammar needs no change; only normative text rules change
the grammar manifest from
`8cef04355f736983a0fcb4ce73551596ce04f370be0ab9c1d4400f81263842ae`
to `f6691d7e84028f06cef976870509421ba61d6f6310f7f32171f8ad5cf6ad422e`.
The Values Run CID becomes
`9ae3da3e9ce0fbc9dc678c2d5a0d00ba7321f47693249f8c51b67fefe0018af7`,
derived from the independent canonical preimage. Historical vectors remain.
Operation registry, schemas, expression laws, Unit and Result Plan are unchanged.
Metadata and generated manifest/canonical vectors follow their normative inputs.

This PR is stacked on #593, whose union source connection is used by the
conflict fixture and whose producer-resolution helper is shared. The eventual
merge target is main; no dependency-branch merge, rebase, force push, manual CI
rerun or PR merge is performed. Other Graph algebra and the overall Frontend
migration remain separate unfinished units.
