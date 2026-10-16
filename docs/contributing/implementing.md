# Implementing ActQL

How the implementation is organised and in what order its parts depend on
each other. This page is for contributors to the Core and the Hosts, and for
anyone implementing ActQL against the specification.

ActQL is implemented in MoonBit against the [specification family](../spec/README.md)
and its pinned machine contracts. Language semantics, wire representations
and content identities come from those contracts, not from another
implementation's internal APIs or limitations. Version assignments follow the
[versioning policy](../design/versioning.md): a reference implementation's
version is never an immutable input to a contract.

Authority is routed through execution-account configuration (allow, deny,
delegate) and the Host's delegated decisions, as the
[execution specification](../spec/execution.md#account-authorization-routing)
defines. Connectors describe technical provider requirements; they do not
grant accounts or hold approval policy.

## Component boundaries

These are responsibilities, not a prescribed directory layout:

- Value and codec foundation: canonical JSON, typed values, equality and
  content identities.
- Protocol admission: schemas, typed reference closure, Catalog and lock
  validation.
- Compiler: source decoding (SQL/Pipe text and the canonical model), scope,
  types, evidence, stage checking and canonical lowering.
- Algebra execution: the pinned algebra contracts and expression evaluation.
- Host: durable capture, budgets, authorization, reservations, fencing and
  recovery.
- Connector boundary: bounded reads, typed commands and authorized reference
  hydration.
- CLI and SDK: authoring, execution control, progress and Result access.
- Conformance: independent positive and negative cases, canonical bytes and
  failure behaviour.

The compiler consumes protocol contracts; protocol definitions do not depend
on compiler internals. CLI and SDK call checked boundaries and do not
redefine semantics. Connectors do not depend on the CLI. Shared encode and
decode code implements one contract across consumers; reuse must preserve
each boundary's scope, closed fields, type validation and demand rules.

### Deployment and Host adapters

The Host connects the Core to environment-specific I/O, storage, credentials
and resource controls; it is not necessarily a separate service.

| Surface | Core target | Host adapter |
| --- | --- | --- |
| TypeScript library | JS | TypeScript |
| Python library | Wasm | Python with an embedded Wasm runtime |
| Cloudflare Workers | JS | TypeScript using Worker APIs |
| CLI | Native | MoonBit with environment-specific FFI where needed |

DuckDB is a physical execution engine, not the definition of ActQL
semantics. A Host embedding a Wasm runtime must also account for native
engine work outside it. Ephemeral storage alone cannot provide the
durability a recovery profile requires.

Shared semantics and execution rules remain in the MoonBit Core. The Local
Host and a managed Host obey the same authorization, idempotency, failure and
recovery contracts; their storage, credential handling and scheduling
adapters differ. The shared Host interfaces and the Local Host are open
source; service-specific integration lives outside the portable Core.

## Bulk execution resource boundary

Physical readers and writers declare streaming or hard-bounded behaviour.
The Host admits their combined live-memory requirement together with
operator state and runtime overhead; the largest component alone is not the
budget. Include decompression, object amplification and concurrent buffers.
Spool and spill paths also require temporary-storage and time limits.
Missing enforceable bounds or unsupported spill paths fail admission rather
than falling back to whole-dataset in-memory execution. Numeric limits are
Host configuration, not Core constants.

Engines such as DuckDB may read staged files directly and produce bounded
output batches without routing every row through a MoonBit object tree. That
placement does not remove checked-contract validation: the adapter must
preserve exact decimals, temporal representations, nested values,
nullability and canonical output rules before claiming result identity.
Storage-byte integrity alone does not establish typed value identity.

## Implementation order

1. Canonical values, UTF-16 ordering, recursive type contracts and content
   identities. Compare fixed bytes and accept/reject cases with independent
   vectors, including nulls, decimals, references, empty values and unknown
   fields.
2. Typed reference traversal, Catalog closure, authority and lock validation.
   Traverse registered reference roles, not strings that look like
   identities.
3. The front end: SQL/Pipe text parsing and lowering to the canonical
   Program model; parameter and default binding, local namespaces, imports
   and exports, evidence propagation and canonical stage and Program
   identities.
4. Core relational algebra and expression execution with shared admitted-root
   validation, collection-wide budgets and demand-preserving evaluation.
5. The common Run Graph, stage activation, durable capture, Checkpoints, the
   logical-item ledger, recovery and source cursor commit.
6. Acquisition, Artifact and the additional algebra profiles against their
   closed contracts. Reject unsupported profiles before external dispatch.
7. CLI and SDK, secure Local Host defaults and generated authoring discovery.
   Verify full scenarios through capture, partial failure, crash and resume.

Each claimed profile requires all of its normative behaviour and independent
execution evidence; the order above does not redefine profile claims.

## SourceView and Effect boundaries

SourceViews produce observations in their declared carrier under the
admitted acquisition contract. Keyed external joins require relation-valued
SourceViews; other consumers keep their own carrier requirements. Requests
use admitted literal or parameter values and opaque bindings under their
closed role contracts. Keyed joins lower to lookup acquisition plus relation
algebra; ranked acquisition uses its own candidate and coverage contract.
Provider reads cannot be hidden in algebra callbacks.

Stage activation respects predecessor success and import availability.
Within a stage, Effects form an unordered set. Concrete previews,
authorization, item conflicts and durable reservations precede dispatch.
Unknown outcomes require reconciliation; retries never erase accounting or
invent success.

Local graph, vector and event carriers are language values. Their existence
does not authorize arbitrary provider APIs, unbounded reads or implicit
mutation.

## Acceptance

- Every claimed contract has positive and negative admission cases.
- Compiler outputs match independent canonical expectations, not snapshots
  promoted from the implementation under test.
- Empty values retain schema, order, policy and completeness evidence.
- Root checks and supplied context contracts hold with or without
  predicates.
- Lookup keys, batches, adopted pages, accounting and evidence closure match
  the registered envelopes through retries and late responses.
- Stage ordering, approval scope, item identity and cursor obligations
  survive crash, cancellation, partial failure and recovery.
- Numeric observations replay captured values; exact numeric paths retain
  their exact laws.
- Dependency pins and builds are reproducible from a clean checkout.
- A release claim identifies exact implementation bytes and its supporting
  evidence under the [conformance rules](../spec/conformance.md).

The Node-based document checks and the independent Python reference lowering
are verification tools; they do not determine the MoonBit implementation's
architecture.
