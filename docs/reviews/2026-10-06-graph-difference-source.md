# Graph difference source connection and publication boundary

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
