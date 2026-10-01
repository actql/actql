# Frontend standard-alignment baseline

Scope: provenance, selected semantics and independent first-unit expectations.
This record does not claim a new Property Graph parser, common Graph model,
runtime path, proof or backend conformance result.

The inspected baseline is `4c4a50cdee1c99ba623af5ec28b12fefddc0e5dd`.
It includes structural-text withdrawal and source-free SELECT/CAST. The
[design ledger](../design/frontend-standard-profiles.md) records references,
adopted boundaries and required semantic changes independently of implementation
delivery. Historical imported sources and their baseline digests remain intact.

## Confirmed gaps and replacement obligations

| Area | Current boundary at the inspected baseline | Required follow-through |
| --- | --- | --- |
| SQL/Pipe composition | Source-free SELECT, SELECT-headed Pipe and relational CTE Pipe paths are present. This corrects the earlier blanket claim that only FROM-headed Pipe is accepted. | Test the full selected parenthesized-query, set-operand and placement matrix separately; existing representative cases are not universal compositional evidence. |
| String literals | `query_syntax/lexer.mbt` emits Text for single quotes and JsonText for double quotes; the query specification reserves the latter for Graph annotation JSON. | Adopt the selected GoogleSQL literal/identifier rules. Verify decoded strings, escapes and backtick names. Inventory raw/triple/bytes forms as supported or unsupported; double quotes must not become identifier quoting. |
| Graph node labels | `query_program/graph_program.mbt` and the query specification map node labels through a selected property field. | Introduce graph-owned label sets at the common construction/admission boundary, then match membership rather than properties. |
| Graph construction and identity | The common identity law keys an edge by source, destination and label; equal declarations can collapse. | Definition-scoped typed keys and separate label sets must survive construction, MATCH/TRAIL and snapshot/reload. Update common laws, schemas, pins, capacity accounting and consumer boundaries together. |
| Graph path profile | Explicit WALK/TRAIL/ACYCLIC, a single MATCH context and bounded quantified shapes are selected restrictions. | Track reference defaults, optional/repeated contexts, quantifiers and element value types individually. A profile restriction is not a statement that GQL itself forbids a form. |
| VecA | The pinned numeric law uses binary32 input quantization, cosine similarity with zero-vector +0, and negative-distance l2 scores. | Do not advertise these as standard distance functions. Compare precision, dimensions, NULLs, zero vectors, overflow, score direction and ties before introducing standard aliases. |
| Temporal surfaces | Common operators and adopted target spellings do not themselves establish an external standard profile. | Select exact event-time, session, recognition and ASOF contracts before freezing those new surfaces. Distinguish analytic frames and event-time membership. |
| INFER and new output scope | Frontend lowering and common execution acceptance are separate obligations. | Formal common-owner handoff, then the minimal packed Local/HTTP execution and KEEP/AS/NULL/replay acceptance; no Frontend execution substitute. |
| RESULT/RECEIPT, EFFECT and sequencing | ActQL-specific adopted targets remain separate from ordinary relation query semantics. | Reuse common authority, durable intent, completion and recovery; do not infer external Effect atomicity from similarly spelled SQL operators. |

## Exact common Graph boundaries

The existing model cannot encode independently keyed parallel edges or node
label membership. These are common-model dependencies, not missing Frontend
punctuation:

| Boundary | Required responsibility |
| --- | --- |
| `src/carrier_contract/carriers.mbt` and `src/graph_typing/construction.mbt` | Describe and admit definition-scoped typed keys, node/edge label sets and complete property contracts. |
| `src/graph_typing/path_contract.mbt` and `src/local_sga/traverse_paths.mbt` | Path identity and TRAIL must retain independent edge keys; ACYCLIC uses full node identity. |
| `src/query_program/graph_program.mbt` | Resolve graph-local definitions and lower label membership against the revised checked contract. |
| `src/bounded_graph_snapshot/` and `src/bounded_graph_diff/` | Preserve identities, labels and multiplicity in canonical snapshots and typed Delta roundtrips. |
| `src/carrier_projection/graph.mbt` and `src/relation_evidence/graph_projection.mbt` | Derive output contracts and uniqueness from complete identities, never the old endpoint tuple. |
| Common capacity, retained storage and publication consumers | Account for the new representation; cancellation/resource failure cannot publish a partial Graph. Unsupported consumers reject rather than downgrade it. |

AoA owns the algebra model and operations; mechanized proof coverage names actual
declarations and assumptions. ActQL connects that model to checking, execution
and lifecycle obligations. Complete mechanization is not added to the bounded
first-unit acceptance. The current INFER completion unit is not expanded by
this record.

## Independent semantic fixture

[Keyed parallel self-loops](../../spec/frontend/fixtures/property-graph/keyed-parallel-self-loops.json)
contains independently authored producer rows and expectations for the adopted
model. It is **not** a Program, wire schema, lowerer output or executed result.
Its classification explicitly remains `runtime_executed: false` and
`common_representation_fixed: false`.

The fixture requires two differently keyed edges on one node to survive. Exact
two-hop paths have four WALK sequences, two TRAIL sequences and no ACYCLIC
sequence. Projecting just endpoints retains four or two duplicate rows rather
than silently making them distinct. Node label Node is independent of the
unselected property `entity_type = 'Company'`. Edge NO PROPERTIES yields an
empty property object while retaining the key and label internally.

The fixture's sequence lists are multiset expectations, not authored Result
ordering. It inserts no Result, sort or storage operation. Snapshot/reload must
retain identities, labels, endpoints and multiplicity, with runtime acceptance
recorded only after the revised common representation is connected.

## Validation boundary

This unit changes explanatory documents and an independent semantic fixture.
It changes no public API, admitted grammar, law/schema/CID, generated runtime,
stored-data reader or execution owner. `machine_program_semantics_preserved`
is clarified relative to the applicable contract pins; its profile marker is
not renamed, and the imported baseline is not rewritten.

Run the existing document/profile checks and the `spec` job through
`scripts/local-checks.mjs`. The fixed implementation SHA and actual results
belong in the PR validation section. Do not count those checks as execution of
the new Graph fixture. Core/native and packed runtime suites need not be
repeated for this documentation-only unit; their prior source-free evidence
does not establish Property Graph conformance either.
