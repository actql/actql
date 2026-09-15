# Initial query physical strategy

`query_planning` consumes `execution_query`'s owned local query preparation described by
[query residual execution](query-residual-execution.md). It neither derives a
canonical acquisition nor introduces a semantic Run, Invocation, approval or
commit scope. Its `AcquisitionChoice` is a Host-private proposal for the same
query, not a public Connector SPI or runnable Plan. The mock's `QueryStrategy`
and fixed two-realization inventory belong to `connectors/mock/acquisition`.

`connector_sdk` owns bounded capability registrations, fixed-input requests,
selected consumer capacities and typed candidate/payload bindings. It depends
only on common execution, lowering and cost contracts. SQL compiler diagnostics
do not appear in its error types. `bind_compute_candidate` validates registration
and the bounded cost inventory; it creates a proposal, not permission to start or
proof of completion. A choice recovers only its exact prepared payload, and
registry closure prevents subsequent recovery without revoking independently
completed outputs. Input accessors retain exact producer handles; the input-array
snapshot cannot mutate owned ports or copy/re-admit the underlying rows.

`CapabilityImplementations[T]` snapshots a bounded, explicit installation of
entrypoints against exact registrations from one Host registry. Installation is
pure: it does not call the entries or create resources. A missing entry denotes
an unsupported operation in that installation; equal names or descriptions from
another registry cannot recover it. The installed set has no mutation or
replacement operation. Closing its registry prevents future lookup, not unloading
of already-recovered code or cancellation of running work. Start and completion
checks remain mandatory after lookup. Typed entries can retain private payloads;
the SDK does not inspect SQL, provider names or resource representations.

`CapabilityBundle[A, C]` is a rebuild-time contribution with independently
optional Acquisition and Compute factories. `install_bundles` validates the
entire bounded manifest before invoking trusted pure factories, derives capability
flags from the supplied entrypoints, and gives each factory its exact registration
in a fresh Host registry. The resulting `InstalledBundles` exposes immutable
operation installations; it cannot append or replace an implementation. Separate
Host installations never recover each other's entries. This bootstrap mechanism
does not load code dynamically or create execution resources; resource bindings
and input locations remain separate from the module's registration.

`physical_host.prepare_installed_dispatch` resolves the selected registration
through that installation and prepares the exact completed input ports before
calling the installed entry. Its context and returned work remain opaque to the
common driver. After preparation it rechecks registry availability and the
current checked-ready selection before issuing a single-use dispatch ticket.
Preparation must not initiate I/O. A ticket is neither a reservation nor a
completion proof; the common execution admission and publication boundaries
remain required.

Acquisition execution, attempts, retention, issuer verification and capture are
owned by `connectors/mock/acquisition` and `connectors/duckdb/acquisition`.
`query_planning` has no concrete connector dependency; it owns shared requirement
and canonical artifact construction plus candidate comparison. Artifact material
is not live evidence: bounded builders neither issue records nor construct
consumer input. Connector issuers associate the material with exact live attempts
and retained values, then install verified capture through `execution_query`.
The serialization budget is opaque and spend-only; record arrays are private,
and observation construction includes previously consumed record bytes/nodes.
No wire or CID rule depends on the implementing package.

The Local realization is owned by `connectors/local`; DuckDB Compute candidate,
receiving and completion state is owned by `connectors/duckdb/compute`. The latter
keeps concrete compiler diagnostics and trusted transport verification separate
from the common request. Existing engine completion ports still verify the exact
retained output before it can be consumed. These package APIs are internal
composition interfaces, not a dynamically loaded or sandboxed plugin ABI.

Package-public functions enable repository-internal composition across MoonBit
packages; they are not a stable provider extension API. The reusable boundaries
are owned checked requirements, pure candidate comparison, completed-input
handoff and validation before capture. `MockQueryIssuer`, `MockQueryAttempt`,
their issuance/lifecycle helpers and the two `QueryRealization` variants model
only the trusted finite in-process source. New providers or shared/grouped
acquisitions must not treat these mock constructors as a general Connector SPI.

The fixed work inventory is cost accounting, not a general coverage proof.
Discharged obligations, auxiliary work and remaining obligations need a separate
shared coverage contract before a general offer/validator interface can be fixed.
Adding another realization enum is not a substitute for that contract or for
canonical derivation of additional acquisition shapes.

Two mock realizations implement the checked finite scan/filter/select shape:

- Native query evaluates complete source admission, filter and select inside the
  mock source, then receives the selected output.
- Broad acquisition receives the broad input, then performs complete admission
  and the checked local residual before the capture boundary.

Both invoke the existing evaluator, rather than duplicating predicate semantics.
Native query is not a weak prefilter: it cannot discharge filter by checking only
returned rows. Physical receipt limits can abort a broad attempt before a value
failure; the same receipt limits apply after source computation in the native
route. The source computation budget and receipt budget are separate.

Requirement-bound mock attempts retain their exact `QueryRequirement` before
execution. They cannot silently use the unguarded diagnostic path: a physical
measurement allowance is required. All known scan values are measured before
predicate evaluation, demanded predicate results obey the requirement's root
byte ceiling, and the complete selected output obeys its row/value guards.
The successful root's already measured size is reused before predicate
consumption; no branch is reevaluated and no logical work is charged twice.

The acquisition's per-value/root guard does not replace the row-kernel's
separately selected limit on complete retained rows, work or live roots. A
root-only ceiling is carried through the private runtime context; existing
checked artifacts and their identities are unchanged. Thus a small scalar
ceiling does not accidentally reject its enclosing row merely for field names
and object delimiters. Measurement work/bytes/nodes are physical bounds shared
across scan and output, not logical work credits. A physical measurement failure
and a measured value exceeding its logical ceiling have distinct typed errors.
Row-limit rejection happens after demanded computation, never as an early take.

## Tasks and accounting scopes

Static `QueryMaterial` retains the exact query preparation, the canonical resolved
request, normalized unevaluated filter identity, and the shared typed identity of
Parameters used by request or filter. Only checked Parameter slots substitute
values; nested business `$param` and `literal` members remain data. Repeated uses
select a value once, including defaults but excluding unused declarations and
binding-origin metadata. Bounded preparation covers name selection, canonical
field order, serialization and hashing before retained artifacts are returned.
This material alone is not a complete canonical acquisition requirement. The
separate `prepare_query_requirement` boundary binds it to a main-owned
`ProgramSourceIdentity`: its retained stage `PipelineRequests` must be the exact
query owner, not a separately constructed equal CID. The owner uses
`program_identity_definition_cid`, including the authored root ID; it does not use
Program semantics or Parameter values as a substitute.

The requirement includes the selected SourceView contract and source reference,
complete checked input/output field-map identities, actual stage-relative
filter/select occurrences, authored projection, all known scan fields and explicit
logical guards. The initial profile emits null source order evidence while
preserving input relative order. Guard selection is retained for execution to
enforce; constructing the requirement does not discharge those checks.
Requirement serialization and hashing share bounded bytes/nodes within that
preparation call; the already-owned `QueryMaterial` has its separately reported
preparation usage. Field traversal and projection copying are preflighted.

This public main source-identity assembly is not the final `CheckedProgram`
source-execution closure. It does not authorize a source, construct a canonical
Plan, issue process evidence or claim a successful observation.

The same requirement entry also consumes the identity returned by the public
`program_check.source_identity` of a `CheckedProgram`. Query derivation and
lowering must use that exact checked Program's stage pipeline and bound values;
rebuilding an equal Program Definition does not transfer ownership. The checked
Unit identity and acquisition requirement remain independent of the chosen mock
route. The main entry retains source Host-combination, authorization, request
egress, resource and response obligations: static construction does not mark
these runtime checks successful. Trusted finite mock setup is not their real
Host/provider implementation or a canonical Plan/Run execution permission.

The physical proposal has `RealizeQuery` followed by `CaptureObservation`.
The edge requires complete query output; it does not permit task-to-task
streaming. Broad receipt and local residual are internal work in the first task,
not new semantic acquisition units. A fixed-input consumer belongs after capture,
not between these internal operations.

The serial cost inventory contains source work, completed receipt transfer,
receipt conversion, residual where applicable, observation capture, output retention
and cleanup. An inclusive
source cost may cover multiple disjoint inventory slots once; including both it
and a duplicate breakdown is rejected. Unknown or missing work estimates remain
unknown. They do not become zero or silently remove a residual/capture stage.
Transfer bytes, retained bytes and money stay separate from duration and from
each other. No estimate is a hard resource bound or preservation proof.

The common cost helper ranks complete estimates by latency and applies supplied
Host priority within an exact tie (enumeration order only when none is supplied).
If any estimate is
unknown, an explicit complete Host-priority ordering is required to propose a
candidate; otherwise selection defers. Offers from a different prepared query are
rejected before comparison. Candidate order, price and route never modify the
shared semantic derivation. All shared runtime requirements remain visible and
pending even after a candidate has been selected.

## Mock execution and capture separation

The synchronous mock attempt copies only a bounded container of immutable source
cursors. No offer, estimate or selection performs I/O. This explicit supplied
finite source is an execution fixture, not proof that an external SaaS/DB source
was observed. Both routes use the ordinary local execution and immutable completed
output implementation. Input failures and expression failures remain typed.

`MockQueryComputation` retains the admitted full scan and completed local output
privately, with actual source
and received row/column counts. There is deliberately no public consumer-output
accessor. This intermediate is not a `completed_observation`, issuer record,
authority decision or capture success. Receipt cells are physical quantities,
not canonical wire bytes or the acquisition's logical row/value guards.

Full-scan admission and query execution share an opaque `execution_query.QueryReceipt`, owned by
the exact query preparation. Keeping this immutable material allows a verifier
to inspect even native rows and columns not received by the Host without a
second admission or reevaluation. Reusing it still runs the driver's input
checks and accounting with a fresh execution budget. It does not establish
external source authority, a snapshot or successful observation capture. Its
retained capacity must be included in capture's physical retention checks;
reduced native receipt is not reduced full-scan retention in this mock.

The canonical rows identity is computed directly from retained input or completed
storage, not by rerunning a predicate or building a JSON row matrix. A bounded
column permutation emits object keys in canonical UTF-16 order while preserving
row order, duplicates, projection layout and zero-column row counts. Nested typed
values use the shared nonrecursive wire emitter; decimals remain fixed-scale
strings. Hash output is bounded by wire bytes, value nodes and container depth;
column metadata and comparison work have separate preparation bounds.

The engine's `RowWireIdentity` keeps its exact immutable `CapturedRows` or
`CompletedOutput` owner, without depending on query receipt types. Matching
its CID does not imply matching that owner, an observation attempt or authorized
issuer. Its byte count includes the complete ordered JSON array and is suitable
for this profile's receipt-wire accounting, not allocator capacity or RSS. It
does not replace per-record/per-root logical limits or physical retention
admission. Failed hashing returns no usable identity and leaves retained data
available for a separately budgeted retry.

`retain_mock_query` applies this measurement to the exact live, requirement-bound
attempt after computation. It retains both full-scan and output identities,
checks actual receipt wire bytes according to the selected route, and bounds the
sum of retained scan and output wire bytes without a sharing discount. Hashing
bytes/nodes are cumulative across those two artifacts; column-order and depth
limits apply separately to each. These explicit wire quantities supplement source
admission and driver container limits, not replace them with a claim about heap
capacity or RSS. No estimate is used to pass retention admission.

An initially invalid measurement configuration is distinct from exhaustion after
successful scan hashing. If the scan consumes the last node allowance, the output
hash fails with an encoding resource limit, not `InvalidLimits`. Even an empty
output array needs a node. Broad receipt-byte rejection still precedes output
measurement when its receipt is already known to exceed the bound.

Both finite mock realizations retain the same full scan plus selected output.
Their actual receipt quantities differ, but this model does not demonstrate a
ranking change caused by different physical retention strategies. Synthetic
retention estimates test accounting and comparison only; they do not establish
that an external native provider can avoid retaining full-scan validation material.

Retention failure fails the owning attempt. Successful retention still precedes
evidence issuance and capture; it exposes usage and row CIDs, not consumer data.
Cancelling this state withdraws the attempt even if another caller holds the
opaque retention handle. Retaining equal data or serialized CIDs cannot restore
the task or create an authorized issuer.

An attempt is one-shot. Failure never changes the selected route or rereads a
source. Cancellation is supported before computation and at the computation/capture
boundary, not during the synchronous evaluator. Cancelling an attempt discards its
references; it does not invalidate other owners' preparations or completed data.
An independently retained intermediate cannot itself authorize capture after the
owning attempt has been cancelled.

The [process-evidence contract](query-acquisition.md) owns issuance and capture
checks. Explicit trusted mock Host setup uses `prepare_mock_query_issuer` with
admitted contract bodies, one exact requirement and a fresh Host process nonce.
The Host is responsible for nonce freshness across process lifetimes; nonce text
alone is not an authority token. Module-owned issuer suffixes distinguish grants
within a process. Attempts have monotonically allocated suffixes before execution,
including failed preparations; exhaustion rejects rather than wrapping/reusing.
Offers and candidates cannot attach this authority after computation. This mock
setup is not external source authorization or a generic Host policy grant.

`issue_mock_query_records` issues all three immutable role records together only
from that attempt's successful retention state. Scope identities come from its
actual selected scan and route-specific receipt; native issuance retains even
nonreceived scan material. The finite mock has no provider snapshot attestation,
so snapshot and provider scope are null. Serialization/hash budgets are cumulative
across scope identities and three records, and failure publishes no record set.

`verify_mock_query_records` requires the Host's expected issuer and task, a live
issuer, the exact issued-set handle installed on that task, and its retained
scan/output ownership. Equal wire or CID does not substitute for live provenance.
Closing the issuer or cancelling before capture prevents verification. Successful
record issuance still does not construct a completed observation or expose a
consumer output; `capture_mock_query` is the distinct admission boundary.

The serialized record and observation do not include the validated full-scan
content CID or row count. `scan_scope_cid` identifies the selected request/source
scope, not its row contents; `actual_access.scope_cid` commits to the received
rows CID and fields. Native receipt covers the selected output, while broad
receipt covers the full scan. The mock binds validated scan contents through the
exact privately retained input identity and live issued-set/attempt ownership,
not through a portable proof in those serialized fields. An external provider
needs an admitted full-scan provenance/attestation path before native capture;
adding a scan CID alone would not prove that its mandatory checks ran.

Observation `coverage.complete` is the closed schema constant `true`, emitted
only after capture verifies the three issued role records. It is not a candidate
boolean accepted as proof, nor a general discharged/remaining obligation model.
General offer coverage and completed-observation admission are distinct contracts;
introducing occurrence-level coverage requires a separately agreed shared design,
not replacing the current constant to repair this process-local verifier.

Capture verifies the expected live issuer/task/record set, recomputes the resolved
request identity and emits the complete shared observation preimage. The three
role CIDs, actual access, scan coverage, snapshot, exact Program Definition owner,
Parameters and retained output stay bound together. Artifact budgets include
scope/record serialization and hashing, request verification and observation
serialization/hashing cumulatively. Any construction failure exposes no successful
observation and invalidates that attempt's pre-capture records.

Only `bind_captured_query_input` releases an existing `BoundProducerInput`, after
checking the exact captured handle on the expected task. It delegates producer
owner, Parameter binding, target and projection checks to `bind_completed_input`;
the ordinary sequence driver still performs receiving admission and accounting.
No source selector, row conversion or second predicate evaluation is introduced.
Successful capture cannot be cancelled as unfinished acquisition. Downstream
failure does not revoke it or authorize a reread; fresh consumer budgets may reuse
the same completed input. Closing the issuer prevents new capture/input bindings,
not the use of already admitted immutable producer inputs. The Host retains the
observation for its process-local evidence lifetime; no durable replay is promised.

Verifier interpretation starts with `admit_query_evidence_contracts`: both the
complete Acquisition contract and the complete process-evidence contract must
hash to the supported pins. The latter includes the record schema and exact
Acquisition dependency. A record schema alone, a version string or a claimed CID
cannot select this verifier. The returned opaque selection retains immutable
bodies; its aggregate byte/node budget spans both hashes without resetting.
This selects interpretation only, not an issuer, task, source authorization or
successful observation. The product record codec is also tested against the
independent shared vectors. Serialization does not confer issuance authority or
restore process-local evidence from JSON.

Real provider attestation, external transfer, durable capture, shared scans,
aggregate absorption, carried-input joins and general streaming need their own
increments. Relation-specific query support does not define all Connector ports;
carrier conversion remains semantic work, not a physical Transfer operation.

## Canonical boundary checks for later increments

These shapes check the boundary design; only the exclusive filter/select shape
has a shared derivation entry. Rows in the table do not independently establish
new canonical units or permit absorption through an existing barrier.

| Shape | Ports, observation and required boundary |
| --- | --- |
| scan → filter → select | Shared derivation owns one declared source input and the select output capture port. Query-internal residual stays before capture. A downstream fixed-input Compute consumes that exact retained observation. |
| scan → group → aggregate | Proposed source-to-aggregate acquisition needs main's absorption and numeric-observation/guard rules. Otherwise capture the source and run checked group/aggregate as later Compute. Neither choice is derived from price. Local group/aggregate kernels and their shared execution contracts are separate prerequisites. |
| One scan shared by two aggregates | One observation must own both consumers' input ports. A shared source capture followed by two Computes is a proposal; two independent fresh reads cannot replace it. A combined multi-output acquisition needs explicit common-observation and joint-completion rules from main. The current exclusive derivation rejects this shape. |
| Captured SaaS input joined with a warehouse source | A retained SaaS input port is fixed data; the warehouse input is a fresh declared source. Whether main derives a carried-input acquisition with output capture, or a separate warehouse capture and a two-input Compute, must be settled semantically. Physical staging/Transfer cannot turn the retained SaaS input into another read. Owned snapshot/port mappings and join execution are prerequisites. |

The same separation applies to Graph, Vectors and Events: a completed port retains
its carrier contract, owner and logical content. Physical relocation or encoding
does not become graph normalization, vector scoring, or an Events window/watermark
operation. Those require their own checked semantic work and demand/limit contracts.
An Events stream is not evidence that this completed-input task edge supports
streaming, and a Relation receipt limit cannot substitute for another carrier's
logical limits. General port support is not claimed by these Relation-only mocks.
