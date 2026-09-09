# ActQL UDF pressure and extension policy

Status: design policy for post-0.1 proposals

Last updated: 2026-09-04

This document is project governance policy, not runtime conformance semantics.
Changing its workload-count threshold does not change the ActQL grammar,
Program meaning, or any protocol CID.

UDF requests are reviewed as either a missing provider-independent operation or
proprietary logic. A repeated provider-independent operation may qualify for a
closed standard operator. Proprietary logic remains data, a typed acquisition
contract, a Run Graph task, or code outside ActQL.

## Pressure map

| Observed pressure | First placement | Why no UDF is needed |
| --- | --- | --- |
| row-local calculation | scalar expression | one typed deterministic value |
| set transform, aggregate, window | RelA or the existing carrier algebra | ordering, cardinality, and bounds stay visible |
| graph, vector, or event calculation | SGA, VecA, or TEA | preserve the existing carrier law |
| proprietary algorithm or remote service | checked external SourceView join or typed `infer` | external observation, egress, cost, and evidence remain explicit |
| Relation-to-bytes | Artifact derivation or `serialize` | immutable content and upload authority remain separate |
| external mutation | Effect | preview, approval, idempotency, and receipt remain reviewable |
| approval before protected work | Host Checkpoint | pause and resume the same Run; do not add source syntax |
| same-Run resume, admitted retry, or reconciliation | Host runtime | preserve the exact continuation, authority, and idempotency identity |
| time, scheduling, later observation, or outcome-driven later work | Run Graph | start or coordinate a later bounded Run |
| arbitrary unverifiable code | outside ActQL / constrained Opaque Task | weaker guarantees remain visible |

The extension policy does not admit these source forms:

```yaml
- udf: {language: python, code: "..."}
- compute: {contract: custom-function:v1}
- transform: {wasm: sha256:...}
- fold: {initial: ..., function: ...}
```

A hash, signature, type declaration, or sandbox does not expose an opaque
function's algebraic law or make it safe to reorder, fuse, push down, replay,
or price before execution.

## Likely future pressure, without pre-adoption

ActQL 0.1 includes exact decimal arithmetic, closed object/array construction,
`assert_rows`, and Unicode/total timestamp helpers. See the
[authoring guide](../authoring.md#row-local-values-and-invariants) and
[conformance requirements](../spec/conformance.md#conformance-tests).
This is not admission of a general UDF boundary.

The following remain plausible gaps, not accepted 0.1 features:

- scalar value refinements such as enum, range, and string-length constraints;
- JSON entry expansion/aggregation, standard text similarity, or one standard
  aggregate/window operator;
- additional typed acquisition outcomes beyond the registered infer contract.

These examples do not authorize generic validators, dynamic object keys,
recursive JSON mutation, fuzzy-join or entity-resolution operations, arbitrary
reducers, `try/catch`, or domain-specific modules. OCR, transcription,
geocoding, tax engines, holiday calendars, routing, optimization, XLSX/XML/ZIP,
and proprietary scoring begin as Relation data or typed SourceView contracts.
Asynchronous forms use Command plus Run Graph. A repeated
provider-independent mathematical meaning may later graduate to the existing
algebra; provider features never graduate merely because they are popular.

## Admission evidence

Before proposing one new operator, collect a UDF-pressure corpus of real code
fragments. Each entry records:

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

1. at least three independent real workload families require the same
   provider-independent semantics;
2. existing composition, Relation-as-data, typed acquisition, Artifact, and
   Run Graph boundaries are materially unnatural or insufficient;
3. input/output types, null behavior, ordering, failure, cost, memory, and
   output bounds can be closed;
4. portable conformance vectors and an independent oracle can be written;
5. no new root Carrier, authority boundary, or execution category is needed;
6. an elimination proof explains what is ambiguous or unsound without it.

If any condition fails, the operation is not added to ActQL.

## Fixed routing rule

```text
existing composition?
  yes -> add nothing
business rule is data?
  yes -> Relation + join
external/provider/proprietary observation?
  yes -> checked external SourceView join or typed infer
bytes?
  yes -> Artifact derivation / serialize / SourceView
time or prior Effect outcome?
  yes -> Run Graph
general deterministic bounded semantics repeated across real workloads?
  yes -> propose one closed operator in the existing algebra
otherwise -> outside ActQL
```

All extension proposals follow this routing rule.

## Future master-data authority

A future MDM module would need to close the following
authority workflow before claiming master-data support:

```text
versioned persistent graph source
→ typed canonical entity and source binding
→ resolution evidence and merge/split proposal
→ graph delta preview against an exact base version
→ affected binding/relation/source-record counts and conflicts
→ required approval bound to the concrete preview CID
→ CAS apply
→ graph mutation receipt and lineage
```

Entity merge and split would be Effects, not SGA calculations. Their previews
would expose moved bindings, rewritten relations, conflicting attributes,
downstream source records, permissions, maximum scope, base graph identity,
and approval requirements. The design would reuse ActQL's monotone approval,
exact authority, preview-CID attestation, idempotency, and receipt principles,
rather than reinterpret `SGA.union` as entity merge.
