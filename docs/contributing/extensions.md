# Proposing extensions

How a request for a new operation, function or user-defined code is
evaluated, and where each kind of need belongs today. This page is project
policy for proposals after v0.1; it does not change the grammar, a Program's
meaning or any contract identity.

ActQL has no user-defined functions, and a proposal is reviewed as one of
two things: a missing provider-independent operation, or proprietary logic.
A repeated provider-independent operation may become a closed standard
operator. Proprietary logic stays data, a typed acquisition contract, a Run
Graph task, or code outside ActQL.

## Where each need goes

| Need | First placement | Why no UDF is needed |
| --- | --- | --- |
| A row-local calculation | A scalar expression | One typed, deterministic value. |
| A set transform, aggregate or window | The relational algebra or the carrier's algebra | Ordering, cardinality and bounds stay visible. |
| A graph, vector or event calculation | The graph, vector or event operations | The carrier's laws are preserved. |
| A proprietary algorithm or remote service | A checked external SourceView join, or a typed `INFER` | External observation, egress, cost and evidence remain explicit. |
| Rows to bytes | Artifact derivation or `SERIALIZE` | Immutable content and upload authority stay separate. |
| An external change | An Effect | Preview, approval, idempotency and receipts stay reviewable. |
| Approval before protected work | A Host Checkpoint | Pause and resume the same Run; no source syntax is added. |
| Same-Run resume, admitted retry or reconciliation | The Host runtime | The exact continuation, authority and idempotency identity are preserved. |
| Time, scheduling or work driven by an outcome | The Run Graph | Start or coordinate a later bounded Run. |
| Arbitrary, unverifiable code | Outside ActQL, or a constrained opaque task | The weaker guarantees stay visible. |

These source forms are not admitted:

```yaml
- udf: {language: python, code: "..."}
- compute: {contract: custom-function:v1}
- transform: {wasm: sha256:...}
- fold: {initial: ..., function: ...}
```

A hash, a signature, a type declaration or a sandbox does not expose an
opaque function's algebraic law, and so does not make it safe to reorder,
fuse, push down, replay or price before execution.

## Likely future pressure

ActQL 0.1 includes exact decimal arithmetic, closed object and array
construction, row assertions, and Unicode and timestamp helpers. The
following remain plausible gaps, not accepted features:

- scalar value refinements such as enum, range and string-length
  constraints;
- JSON entry expansion and aggregation, standard text similarity, or one
  more standard aggregate or window operator;
- additional typed acquisition outcomes beyond the registered `INFER`
  contract.

These examples do not authorize generic validators, dynamic object keys,
recursive JSON mutation, fuzzy-join or entity-resolution operations,
arbitrary reducers, `try/catch`, or domain-specific modules. OCR,
transcription, geocoding, tax engines, holiday calendars, routing,
optimisation, XLSX/XML/ZIP handling and proprietary scoring begin as
Relation data or typed SourceView contracts; asynchronous forms use a
Command plus the Run Graph. A repeated provider-independent mathematical
meaning may later graduate into the algebra; a provider feature never
graduates merely because it is popular.

## What a proposal needs

Before proposing one new operator, collect a corpus of real code fragments
that need it. Each entry records:

```text
source_fragment_cid
input_contract_cid
output_contract_cid
shape: row_local | aggregate | pairwise | artifact | external | process
deterministic_after_capture
external_io
stateful
current_actql_expansion
unexpressible_reason
independent_workload_family
```

An operator proposal is eligible only when all of these hold:

1. At least three independent real workload families require the same
   provider-independent semantics.
2. The existing composition, Relation-as-data, typed acquisition, Artifact
   and Run Graph boundaries are materially unnatural or insufficient.
3. Input and output types, null behaviour, ordering, failure, cost, memory
   and output bounds can be closed.
4. Portable conformance vectors and an independent oracle can be written.
5. No new root carrier, authority boundary or execution category is needed.
6. An elimination proof explains what is ambiguous or unsound without it.

If any condition fails, the operation is not added.

## The routing rule

```text
existing composition?
  yes -> add nothing
business rule is data?
  yes -> Relation + join
external / provider / proprietary observation?
  yes -> checked external SourceView join or typed INFER
bytes?
  yes -> Artifact derivation / SERIALIZE / SourceView
time or a prior Effect outcome?
  yes -> Run Graph
general deterministic bounded semantics repeated across real workloads?
  yes -> propose one closed operator in the existing algebra
otherwise -> outside ActQL
```

All extension proposals follow this rule.

## Master data

A future master-data module would need to close this workflow before
claiming support:

```text
versioned persistent graph source
→ typed canonical entity and source binding
→ resolution evidence and merge/split proposal
→ graph delta preview against an exact base version
→ affected binding/relation/source-record counts and conflicts
→ required approval bound to the concrete preview identity
→ compare-and-set apply
→ graph mutation receipt and lineage
```

Entity merge and split would be Effects, not graph calculations. Their
previews would expose moved bindings, rewritten relations, conflicting
attributes, downstream source records, permissions, maximum scope, base
graph identity and approval requirements — reusing ActQL's approval,
authority, preview-identity, idempotency and receipt principles rather than
reinterpreting a graph union as an entity merge.
