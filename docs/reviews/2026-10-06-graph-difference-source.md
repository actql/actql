# Graph difference source connection and publication boundary

## Common order repair and current integration

Normally merged main `92e789981a77eb3b229eaf01a289733ca768aa2a`.
The combined grammar preimage is
`sha256:b43a9bd5a9e433dd164afd4760f583cee1d29e63e8eb65200dc9adbfd54bc095`;
the independently assembled current Values Run is
`sha256:aeaec36c0401892a5b3ccb6b09ded8f9d077a500e36eb9f4650c6cd14a97ea80`.
Both original merge-parent vectors and all pre-membership identities remain
unchanged. No product-returned CID supplies an expectation.

The existing language contract states that graph_diff completes exactly one
Delta row. `local_sga/delta_diff.mbt` completes its bounded output through the
existing one-row import. `pipeline_typing/logical_order.mbt` now retains the
checked `GraphDelta(Difference)` producer as the logical order origin. Legal
projection/filter/take consumers preserve that evidence. Graph application
returns a Graph and does not establish Relation order. The Result publication
policy and all its refusal conditions are unchanged.

Before repair, the independent Program, its authored source and the consuming
publication tests failed 4/8 (`run-5GfcAL`). With the repair, the same consumer
boundary plus existing Delta/Result policy guards passed 18/18 (`run-eqks7R`).
An additional negative control verifies that a one-row ceiling on an arbitrary
JSON Relation still has no logical order and rejects publication with exactly
`UnresolvedOrder`. It and the source/Values consumer passed 10/10
(`run-fXXUD6`). That attempt's Node phase passed 13/14, finding main's stale
COUNTIF flag-position assertion; the focused correction passed 2/2 with
read-only manifest/import/canonical freshness (`run-H7FAJo`, 370 identities).

Authored public fixtures compare full Delta content and snapshot identities:
independent JSON controls with two separately keyed parallel edges, source
self-difference, quoted aliases/normalization, nonempty parallel-edge removal
within one domain, and an empty typed Relation suffix. Expected producer trees,
Graph contracts, snapshots and Delta actions are authored without a product
compiler, canonicalizer or difference result. Both ordinary and narrow packed
routes retain the same cases; eight preparation refusals preserve zero
admission/provider I/O assertions. They reuse existing resend/attach/describe/
read checks and never supplement a compiled Program.

Public Local/HTTPS results and exact package/source digests will be recorded
for the clean submitted SHA in the PR body. They are not claimed by these
focused checks. Full Core, Wasm/native runtime and required CI remain separate.
The sections below preserve the earlier unresolved-order evidence at its
original source; they are historical, not the status after this repair.

The first ordinary pack at `5770a22a0e7473930b6c51eb16632dec27103cb1`
passed actual retained-history validation and package production, then refused
the first machine control before admission (`run-bm5quJ`). The authored fixture
incorrectly used `mode: "none"`; the pinned constructor requires
`mode: "no_properties"`. The nonempty removal control also used the currently
unsupported `subtract_graphs` consumer. Correct the constructor spelling and
produce the same empty target with the supported `subgraph` selector over an
empty typed identity Relation. Keep the independently expected node and both
edge removals; no result value, Host ceiling or product contract is weakened.
The same built checker with the unchanged standard constructor ceilings prepares
all six corrected cases (`run-1h38LY`). This diagnostic is preparation evidence,
not a new-SHA packed execution success.


Base: fetched main `94754f064299082a4cc4e44024dc8a844118f8ee`.
This unit reuses the admitted Property Graph contract and the existing
`graph_diff` operation. It adds no Graph kernel, execution owner, serialization
profile, identity mapping, acquisition or compatibility fallback.

## Minimal source and independently authored Program

```aql
DATA n = SELECT 1 AS node_key, 7 AS p;
DATA g = PROPERTY GRAPH (
  NODE TABLES (n AS N KEY (node_key) LABEL Person PROPERTIES (p))
);
FROM g |> graph_diff(with: g) |> SELECT delta
```

The complete expected ordinary Program is independently authored in
`src/query_program/graph_difference_rows_test.mbt::graph_difference_expected`.
It contains one constructor, a `graph_diff` step whose left and right inputs
both reference that constructor, and the explicit `delta` projection/Result.
No product-emitted Program or Delta supplied this expectation. An admitted
self-difference should produce one non-NULL JSON Delta value with no actions,
whose base and target snapshots agree. Runtime admission and canonical snapshot
identities remain obligations of the common Delta owner.

Before the Frontend repair, the source was rejected as `UnsupportedGraph`:
`script_has_graph_rows` omitted `graph_diff`, and the Graph-preserving lowerer
rejected its Relation output. The new Graph-to-Relation branch shares existing
`with:` producer resolution with `graphs_equal`; it emits the existing step and
only the common `delta` column. Quoted DATA names and retained aliases reference
the existing producer. Unknown, forward and Relation references, missing/extra
arguments, repeated Carrier transitions and hidden Graph columns are refused.

## Separate common-owner dependency

The independent Program is rejected by the ordinary checker with exactly:

```text
Source(SourceView(Program(Program(Order(0,
  ResultOrder(UnresolvedOrder))))))
```

The source after repair reaches the same refusal. This is not an executed
Delta result or a public Local/HTTP success. The existing regression in
`src/relation_results/graph_singleton_order_test.mbt` explicitly establishes
that Graph Delta row-count information does not invent publication order.
`graph_typing/delta.mbt::check_graph_diff` provides the complete Relation type;
`pipeline_typing` provides a singleton row bound but no logical order;
`relation_results::resolve_publication_order` cannot publish its JSON field.

The common order/evidence owner needs to connect sound completion order for
this existing bounded singleton producer, including propagation through legal
Relation operations and the Result publication path. A generic claim that all
row-count bounds imply ordered execution would be insufficient. The Frontend
does not change that contract, add evidence, stringify the Delta, discard a
Result or alter an authored order to make the example pass.

After that dependency is resolved, use the same authored source and independent
Program from a clean fixed SHA in packed Embedded Local and authenticated HTTP.
Compare the actual Delta, complete JSON column contract, ordered field list,
stream completion and same-Run resend/attach/read behavior. Include a
same-domain nonempty subgraph difference with distinct parallel edge keys.
Preparation refusals must leave Run admission and provider I/O at zero.
Those public execution obligations remain unverified in this unit.

## Identity and fixture alignment

The query-text rule update binds Grammar Manifest
`sha256:2ab971016048d6d5f3c15dd4f18319b2f7239af4fdfc1829fe0869233be323bb`.
Its document imports, generated compiler pins and canonical identity vectors
are regenerated from the actual normative bodies. Versions remain 0.1.

The consuming fixed Values tests also retained identities from before main's
expression/Program-schema/AoA updates. The independent Node oracle now authors
the current Program semantics around its explicitly selected Stage roles and
derives its Definition, Unit, Result Plan, request intent and Run preimages.
Historical vectors use frozen predecessor dependencies and AoA pins instead of
being rebound to whatever contract happens to be installed. The checkpoint
`36aa2feaa20defd44b0a9b9a05531dc5e3bdff72` retains its original grammar pin
and Run CID; it is not relabeled as current main.

The current fixed Program Definition is
`sha256:1be70a67bfbb6438998862777b118114f9c091a9bb4312a14963dd85edc228cd`;
the grammar-bound Values Run is
`sha256:10f3c4f2a1906ab3ee3f4734d2287e9541283f9142f10346a80bce031045da58`.
These are independently calculated expectations, not replacements copied from
an issuer's returned CID. This fixture repair changes no runtime contract.

## Focused evidence

- Pre-fix JS, source `5c4e74605220eeced2171d0ec169ebde4b098315` plus the
  independently authored test: two failures, one missing Frontend connection
  and one common Result-order refusal. Evidence:
  `_build/local-checks/attempts/run-9HHdxs` and
  `_build/focused-evidence/focused-test-rsIP6z`. These are historical baseline
  observations; they are not execution at the fetched main SHA. The relevant
  Frontend/checker files did not change between the two main commits.
- Focused JS after connection, including the existing equality caller:
  13/13 passed. Command: `node scripts/local-checks.mjs test moon
  --timeout-seconds 300 -- --target js
  src/query_program/graph_difference_rows_test.mbt
  src/query_program/graph_equality_test.mbt`. Evidence:
  `_build/local-checks/attempts/run-ZYSlkZ` and
  `_build/focused-evidence/focused-test-tg0McT`.
- The successful refusal regressions establish the exact common boundary;
  they do not satisfy normal execution acceptance. Packed Local/HTTP,
  Wasm/native execution and exact submitted-SHA CI remain unverified.
