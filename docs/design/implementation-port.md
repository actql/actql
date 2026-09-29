# MoonBit implementation guide

ActQL is implemented in MoonBit against the [specification family](../spec/README.md)
and its pinned machine contracts. Language semantics, wire representations and
CID preimages come from those contracts, not from another implementation's
internal APIs or limitations.

The agreed [authorization design](host-authorization.md) separates Core
execution-account settings from Host application-user authorization and delegated
decision handling. Its configuration and protocol definitions remain pending.
Implement it against coordinated normative/wire owners, not this design guide
alone. Connectors describe technical provider requirements, not account grants
or business-approval policy.

Owned version assignments are maintained here as well. Follow the
[versioning policy](versioning.md) when reusing contract bodies or
identity code; a reference implementation's version is not an immutable input.

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

### Deployment and Host adapters

The Host connects the core to environment-specific I/O, storage, credentials
and resource controls; it is not necessarily a separate service. Possible
adapter targets are:

| Surface | Core target | Host adapter |
| --- | --- | --- |
| TypeScript library | JS | TypeScript |
| Python library | Wasm | Python with an embedded Wasm runtime |
| Cloudflare Workers | JS | TypeScript using Worker APIs |
| CLI | Native | MoonBit with environment-specific FFI where needed |

These are integration targets, not claims of available distributions or a
service deployment plan. DuckDB is a physical execution engine, not the
definition of ActQL semantics. A Host embedding a Wasm runtime must also account
for native engine work outside it. Ephemeral storage alone cannot establish
the durability required by a selected recovery profile.

Shared semantics and execution rules remain in the MoonBit core. OSS Local Host
and Cloud Host obey the same authorization, idempotency, failure and recovery
contracts. Their storage, credential handling and scheduling adapters differ;
Cloud additionally supplies namespace isolation and shared-resource controls.
The shared Host interfaces and Local Host belong in OSS; Cloud-specific service
integration belongs outside the portable core. These interfaces do not prescribe
a service's deployment topology, storage product or implementation language.

## Bulk execution resource boundary

Physical readers and writers declare streaming or hard-bounded behavior. The
Host admits their combined live-memory requirements with operator state and
runtime overhead; the largest component alone is not the memory budget. Include
decompression, object amplification and concurrent buffers. Spool/spill paths
also require temporary-storage and time limits. Missing enforceable bounds or
unsupported spill paths fail admission rather than falling back to whole-dataset
in-memory execution. Numeric limits remain Host configuration, not core constants.

Use [row/batch admission](value-admission.md#bulk-row-admission-boundary) for
row-local validation. Engines such as DuckDB may read staged files directly and
produce bounded output batches or parts without routing every row through a
MoonBit object tree. That placement does not remove checked-contract validation:
the adapter must preserve exact decimals, temporal representations, nested values,
nullability and canonical output rules before claiming ActQL result identity or
equivalence. Storage-byte integrity alone does not establish typed value identity.
Unsupported mappings are rejected wherever the requested contract requires them.

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
