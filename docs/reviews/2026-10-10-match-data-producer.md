# Projected Graph MATCH as a DATA Relation producer

Base: main at 30df1244a6bcb5d32829ac928a72d96a37125e33.
Integration also includes main ca93fba102c368bc9907e25e02bba9f6cfdbc486.
The only conflicts are the generated registration inventory and its fixed count
assertions; both retain the new main fixtures plus this unit’s 10/7 cases.
Owner: B, frontend syntax, lowering and direct public acceptance. No dependency
on the unmerged Graph Relation JOIN work or a new execution owner.

## Counterexample and existing common control

The ordinary Program already admits Values -> Graph -> match_nodes -> select
-> sort -> Named Result through the normal checker. A terminal projected
Graph MATCH also uses the existing keyed lowerer. This complete text did not
reach that lowering when the projected Relation was bound to DATA:

~~~aql
DATA n = SELECT 1 AS node_key, 7 AS p;
DATA g = PROPERTY GRAPH (
  NODE TABLES (n AS N KEY (node_key) LABEL Node PROPERTIES (p))
);
DATA chosen = FROM GRAPH g |> MATCH WALK (a:Node) |> SELECT a.p AS value;
FROM chosen |> ORDER BY value
~~~

Before the fix, the independently authored JSON control passed the normal
checker and the source failed syntax: local gate run-hHcj9M, focused evidence
focused-test-irole9, 0/1. After the minimal connection, the same test passed:
run-M60GYz, focused-test-bEJOjC, 1/1. These are focused checker observations,
not packed execution evidence.

## Change and preserved boundaries

Only the DATA query parser enables Graph MATCH in a declaration body. Ordinary
CTE/derived-table Graph restrictions and INFER/Effect placement remain intact.
The DATA lowering branch calls the existing keyed MATCH lowerer and retains
only its explicitly projected Relation columns. Pattern aliases and private
identity/path slots do not enter the new DATA scope. Graph-preserving calls and
ordinary Graph row extraction keep their existing branches.

DATA cannot export nested Results. The keyed terminal lowerer accepts retained
Result declarations, so the DATA call rejects them with UnsupportedResult
before calling it. No Result is silently discarded. Duplicate DATA names remain
parser errors; the implementation does not introduce DATA name replacement.

The grammar now declares the DATA MATCH body explicitly. This is an ActQL DATA
composition extension over the adopted Graph pattern surface, not an assertion
that the previous grammar already admitted it. No Graph CTE support, executor,
materialization, key guarantee, sort implementation or compatibility route is
added. Identity, label membership, NULLs, path multiplicity and capacity remain
with the existing common owners.

## Independent expectations and identity

The MoonBit fixture compares the entire lowered Program against a separately
authored Program. Public fixtures pair source inputs with ordinary JSON controls
and explicit expected rows, ordered columns and nullable contracts. They cover
NULL, empty results, quoted DATA names, ordinary Relation star, normalization
before MATCH, two keyed parallel self-loops under two-hop TRAIL, and acquired
producer reuse across two explicit Results. Expectations are not generated from
compiler/evaluator output. The existing public harness checks describe/rows,
internal-column absence, request resend, Result reread and acquisition counts.

Grammar changes move the grammar-bound Run identity even for the fixed Values
fixture. The independent preimage calculator reproduces and retains the complete
prior grammar and Run in pre-match-data-producer-grammar.json:

- Prior Run: sha256:fa57a9c0f667cae5597a30f9cf4606c86d3c15620526d757f7942e16129b01bf.
- New grammar manifest: sha256:ec13ddab1832acf1745caf3c5731b753cf26987d50c9049d36d3bba15d1c3f69.
- New Run: sha256:ab7325f123e6883501adb0ed7b70c6b55065798c1b32a9edef1562a6f0d23a91.

Program, Values Unit and ResultPlan identity preimages are unchanged. Old Runs
are not relabelled. Generated manifests, document metadata and canonical vectors
come from their existing generators; fixed Run expectations come from independent
preimages rather than an issuer's observed output.

## Limited verification

Pinned Node 22.22.0 and MoonBit 0.10.12+1634b282e were used.

- Focused JS MATCH/DATA/syntax callers: 22/22, run-sHK0rV,
  focused-test-PqBnwM.
- Public source/JSON checker controls plus grammar-bound Run-materials caller:
  9/9, run-LH5ESo, focused-test-Jyfww9.
- Targeted Node fixtures, registration inventory, grammar manifests, normative
  imports and independent Run vectors: 45/45, run-erw9JA,
  focused-test-Z4VKL2.
- Read-only compilation manifests, document metadata, spec family and canonical
  identities: successful; 382 canonical identities matched generated inputs.

All local evidence paths are beneath this worktree's _build/local-checks/attempts
and _build/focused-evidence. A test-only helper visibility error and invalid
assumptions about duplicate DATA names/parser-level Result refusal were corrected;
these intermediate failures were not treated as product execution failures.

Fresh packed Embedded Local/HTTPS acceptance of 10 normal cases and 7 preparation
refusals is pending at this commit. It must use normal five-package packing from
a clean exact SHA, verify manifest/digests, and retain transport receipts. Pure
syntax/checker success does not establish Host execution. Full Core, Wasm/native,
full packed campaigns and submitted-SHA CI are not claimed here. This unit does
not close the entire frontend objective or the separate ordered graphs_equal
JOIN common-owner gap.
