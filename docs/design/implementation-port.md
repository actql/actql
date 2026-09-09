# MoonBit implementation guide

ActQL is implemented in MoonBit against the [specification family](../spec/README.md)
and its pinned machine contracts. Language semantics, wire representations and
CID preimages come from those contracts, not from another implementation's
internal APIs or limitations.

## Component boundaries

The following are responsibilities, not a prescribed directory layout:

- Value and codec foundation: canonical JSON, typed values, equality and CIDs.
- Protocol admission: schemas, typed reference closure, Catalog and lock validation.
- Compiler: source decoding, scope, types, evidence, stage checking and canonical lowering.
- Algebra execution: pinned AoA contracts and expression evaluation.
- Host: durable capture, budgets, authorization, reservations, fencing and recovery.
- Connector boundary: bounded reads, typed commands and authorized reference hydration.
- CLI and SDK: authoring, execution control, progress and Result access.
- Conformance: independent positive/negative cases, canonical bytes and failure behavior.

The compiler consumes protocol contracts; protocol definitions do not depend
on compiler internals. CLI and SDK call checked boundaries and do not redefine
semantics. Connectors do not depend on CLI. Shared encode/decode code implements
one contract across consumers; reuse must preserve each boundary's scope,
closed fields, type validation and demand rules.

## Implementation order

1. Implement canonical values, UTF-16 ordering, recursive type contracts and
   CID calculation. Compare fixed bytes and accept/reject cases with independent
   vectors, including nulls, decimals, references, empty values and unknown fields.
2. Implement typed reference traversal, Catalog closure, authority and lock
   validation. Traverse registered reference roles, not CID-looking business strings.
3. Implement the stage root grammar, parameter/default binding, local namespaces,
   imports/exports, evidence propagation and canonical stage/Program identities.
4. Implement Core/RelA and expression execution with shared admitted-root
   validation, collection-wide budgets and demand-preserving evaluation.
5. Implement the common Run Graph, stage activation, durable capture,
   Checkpoints, logical-item ledger, recovery and source cursor commit.
6. Implement acquisition, Artifact and additional algebra profiles against their
   closed contracts. Reject unsupported profiles before external dispatch.
7. Connect CLI/SDK, secure Local Host defaults and generated authoring discovery.
   Verify full scenarios through capture, partial failure, crash and resume.

This sequence does not redefine profile claims. Each claimed profile requires
all of its normative behavior and independent execution evidence.

## SourceView and Effect boundaries

SourceViews produce observations in their declared Carrier under the admitted
acquisition contract. Keyed external joins require relation-valued SourceViews;
other consumers retain their own Carrier requirements. Requests use admitted literal/parameter
values and opaque bindings under their closed role contracts. Keyed joins lower
to lookup acquisition plus relation algebra; ranked acquisition uses its own
candidate/coverage contract. Provider reads cannot be hidden in algebra callbacks.

Stage activation respects predecessor success and import availability.
Within a stage, Effects form an unordered set. Concrete previews, authorization,
item conflicts and durable reservations precede dispatch. Unknown mutation
outcomes require reconciliation; retries never erase accounting or invent success.

Local graph, vector and event carriers remain language values. Their existence
does not authorize arbitrary provider APIs, unbounded reads or implicit mutation.

## Acceptance

- Every claimed contract has positive and negative admission cases.
- Compiler outputs match independent canonical expectations, not snapshots
  promoted from the implementation being tested.
- Empty values retain schema, order, policy and completeness evidence.
- Root checks and supplied context contracts hold with or without predicates.
- Lookup keys, batches, adopted pages, accounting and evidence closure match
  the registered envelopes through retries and late responses.
- Stage ordering, approval scope, item identity and cursor obligations survive
  crash, cancellation, partial failure and recovery.
- Numeric observations replay captured values; exact numeric paths retain
  their exact laws.
- Dependency pins and builds are reproducible from a clean checkout.
- A release claim identifies exact implementation bytes and its supporting
  evidence under the [conformance rules](../spec/conformance.md).

Node-based document checks and the independent Python reference lowering are
verification tools; they do not determine the MoonBit implementation architecture.
