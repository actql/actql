# Common Engine and Site Architecture Implementation Plan

Date: 2026-09-18. Owner: common execution engine.

The paired Local Compute plan is
`2026-09-18-local-compute-implementation.md`, owned by the separate Local
Compute branch. This plan builds on
[retained correctness and the Local Compute boundary](retained-correctness-local-compute-readiness.md)
and sections 19 through 21 of
`reviews/2026-09-12-actql-physical-connector-proposal.md`.

## 1. Objective and completion boundary

Restructure the existing common execution management so it can be placed
across a Coordinator and Execution Site Agents. Establish the separation in
one process first and proceed independently from the Local Compute expansion.
A Connector is an implementation of computation, acquisition, or another
capability. A Site is a location that executes work and retains data. Do not
encode a fixed mapping such as Local equals PC or DuckDB equals container.

The Host represents the contract-level responsibility for the whole run. The
Coordinator selects candidates and performs authorization and common
admission. A Site Agent performs the admitted execution, verification,
retention, stopping, and reclamation. A Site success response or a CID string
never substitutes for common completion, including after a future remote
split.

The initial implementation comprises E0 through E3. It must establish an
in-process Site and a standard path that transfers between two in-process
Sites. E4 and later milestones are independent follow-up work and do not block
Local Compute development. Judge implementation completion and merge readiness
separately for every milestone.

### 1.1 Fixed decisions for the first implementation

The scope is E0 through E3 only. Formal Result publication, remote execution,
credential grants, resident optimization, and formal performance acceptance
are separate milestones. Check existing paths for regressions, but add no new
performance target here.

- A Site is a location and generation responsible for execution, retention,
  and reclamation. It is not an alias for a Connector registration. Permit the
  same implementation at multiple Sites and multiple implementations at one
  Site.
- Only the common Host or Coordinator commits common completion. An adopted
  common verifier may execute at a Site; this does not require the Coordinator
  to receive and revalidate every row. The Coordinator verifies the exact
  binding between attempt, obligations, material, and retention.
- Keep the existing ledger authoritative. Site-specific pools are resource
  scopes within that authority. Do not add a second ledger or success state
  machine.
- A Transfer is an explicit managed operation with its own attempt,
  reservation, cancellation, stop confirmation, and reclamation
  responsibility. It is not a language task.
- Separate Site discovery identity from dispatch authority. Dispatch admission
  also checks the exact task and attempt, input-use rights, authorization, and
  reservation.
- The engine branch must not depend on unmerged Local branch work. Complete it
  against the minimal Local implementation at the fixed baseline. Publish
  shared SDK changes as small compatible commits.
- Candidate comparison uses side-effect-free advertisements. After selection
  and before dispatch, recheck the Site generation, authority, and capacity,
  then establish the binding and reservation. Do not implement automatic
  reselection or retry at another Site in this milestone.

The first Transfer uses a bounded in-memory representation supported by the
minimal Local implementation and creates an independently owned destination
material generation. Bounded row wire is the first supported codec, not a
mandatory format of the common Transfer API. Move it in bounded batches and do
not construct an array containing the entire wire payload. Relabelling a
physical handle with another Site identity is not conforming.

Site teardown separates stopping new admission from releasing existing
responsibilities. After admission stops, continue to accept settlement,
holding release, and cleanup retries for existing operations, while rejecting
new consumer admission. Teardown is not complete while a holding, an
unconfirmed operation, or unreclaimed responsibility remains. Forced loss is
an explicit generation revocation.

The required failure matrix covers binding failure, cancellation during
transfer, delayed stop, capacity exhaustion, corruption, generation mismatch,
destination-generation failure, cleanup failure and retry, and multiple
consumers.

## 2. E0: fix the baseline and ownership boundary

The fixed baseline is
`5a305f3ce5cdac421985fb9a71878bc22af51237`. It contains the ownership-boundary
fix in `1685b717` and the dependency-free gate coverage in `5a305f3c` after
`01d5b732`. Passing the 29 focused tests for the two P2 fixes does not imply
that every gate or Linux CI passed at this final SHA.

Record the following for the handoff SHA:

- Regression coverage for exact-attempt completion and issuance, memory and
  file use rights, arbitrary thrown values, stop confirmation, and
  reclamation.
- The four common conditions: typed AoA view, pre-start eligibility, common
  completion, and an operation-name-independent DAG.
- Toolchain and dependency pins, all local gate results, Linux CI status,
  unsupported features, and remaining performance work.

Create the engine and Local branches from this SHA. All required local gates
define implementation completion. Required Linux CI on the same SHA defines
merge readiness. Development may continue while CI is pending, but merge to
main only after merge readiness is established. Do not relabel unfinished
performance work as complete.

| Common engine owns | Local team owns |
| --- | --- |
| `connector_sdk`, `physical_strategy`, and `physical_host` | Local capabilities, kernels, evaluators, and Local storage internals |
| Public common AoA view, completion, attempt, issuer, producer use, retention, and managed bridge APIs | Operation-specific conformance tests and Local benchmarks |
| Node and Workers Hosts, Local driver lifecycle integration, common Store, and bundle generation | Local-specific payload and support logic; use a shared commit when integration must change |
| Site, Transfer, credential, and remote protocol | Site-independent synchronous execution |

`execution_relation` is a mixed-ownership package, so maintain a file-level
ownership table for files changed by this work. Isolate common changes in small
compatible commits that the Local branch can adopt. Do not change the Local
public integration surface unilaterally. A backward-incompatible change to
meaning, mandatory conditions, or state transitions requires the existing
versioning and semantic-decision process, including coordinated dependency-pin
and fixture updates.

## 3. E1: extract the in-process Site Agent

Place a thin Site Agent between the standard Host and Connector contributions.
Reuse the existing typed dispatch channel, exact registration, TaskExecution,
ledger, and completion. Do not add another success decision or ledger.

| Coordinator responsibility | Site Agent responsibility |
| --- | --- |
| Fix checked requirements and mandatory policy; compare candidates | Verify the registered runtime and Connector revision |
| Authorization, budgets, and task, attempt, and strategy management | Dispatch in the selected environment and use physical resources |
| Completion and publication admission | Execute value validation and required measurement or identity work |
| Track unconfirmed stop and reclamation responsibility | Retain material, pin inputs, confirm stop, and report reclamation |

The Site may run an adopted common verifier. Document which verifier establishes
each fact and its trust boundary. Responsibility separation must not force the
Coordinator to rescan all values.

Within one process, use opaque handles and typed payloads directly. Do not
force a JSON round trip in anticipation of future RPC. The common surface must
distinguish candidate description, selected binding, dispatch, cancellation
request, stop confirmation, retention, and reclamation state. A Site binding
is fixed to the Site identifier, Site generation, runtime and registration
revision, and contract pins. Discovery information before generation binding
has no execution authority.

Consolidate repeated standard-entry assembly behind a thin facade that invokes
the existing typed phases. Preserve `NeedsInputs`, typed diagnostics, distinct
budget units, and ownership checks. Do not delete lower-level `Prepared` or
`BoundPrepared` APIs merely because the facade removes repetitive code. Do not
fix the common facade result type to Local's `GeneratedSequence`; connect it to
common requests and ordinary candidate selection. The Local branch may keep
using the current standard Host entry while this facade is under development.

Acceptance criteria:

- Finite Local, DuckDB, and reference implementations and Workers use the same
  Site surface. Workers must keep conformance that executes the existing
  standard path through the Site surface, not only a static API check. The
  two-Site Transfer E2E runs on Node.
- The Node Local-only entry works without a DuckDB dependency.
- No Connector name or Node or Cloudflare dependency enters common Core.
- Values, order, identity, failure, and charging match behavior before the
  extraction.
- Site teardown and Result holding release remain distinct, and no unconfirmed
  stop or reclamation responsibility is lost.

## 4. E2: connect Site binding to normal candidates and dispatch

Compare candidates by implementation, applicable obligations, input
representation, execution location or required environment, capacity, and
cost. A Site advertisement is discovery information, not execution authority
or a capacity reservation.

Distinguish an existing Site from an unresolved Site slot that a Provider may
supply after selection. Candidate enumeration, support checks, and preparation
must not start a process, pin an input, reserve execution resources, or perform
external I/O. Planning work remains budgeted.

Dispatch binds the exact task, attempt, strategy revision, registration and
implementation revision, contract pins, Site generation, input bindings and
use rights, guards, budgets, and retention conditions. A Site restart,
revocation, or configuration update invalidates an old binding.

Compose the corresponding duration work for startup, transfer, conversion,
import, computation, output retention, and cleanup. Do not count one shared
transfer twice, and do not merge physically distinct transfers merely because
their CIDs match. Unknown work is never zero. A fixed `1ms` managed estimate is
not a completed cost model.

Capacity estimates require safe upper bounds. Duration costs are predictions;
fix their method, assumptions, and unit rather than demanding a proven upper
time bound. Exclude a candidate lacking a required estimate from automatic
multi-Site comparison, using a diagnostic distinct from semantic
incompatibility. Map startup, transfer, conversion, computation, retention,
and cleanup duration into the existing duration comparison. Do not combine
capacity or money into a scalar with incompatible units.

Retain the existing stable registration-key rule for equal costs. Define a
stable candidate order when the same registration exists at multiple Sites.
Never depend on registration order, response order, or a backend-name priority.

Acceptance criteria: with two in-process Sites and multiple candidates, reject
a foreign Site or generation, stale strategy, and revoked binding before
start. Changing startup and transfer costs must select the appropriate
candidate. A failure after selection must not silently rerun at another Site.

## 5. E3: connect explicit Transfer and retention

Initially transfer only completed immutable fixed inputs. Even between two
Sites in one process, verify the source representation, destination port,
codec, capacity, authorization, and retention. Never reuse a handle by changing
only its Site identifier. The first implementation creates a destination-owned
managed memory generation from bounded row-wire batches, without making row
wire a common Transfer requirement.

1. Verify the exact source generation, use authority, and egress conditions,
   then retain a scoped source use right.
2. Reserve destination construction and retention capacity.
3. Transfer bounded batches and verify values, order, and integrity under a
   registered preservation rule.
4. Admit the destination only after its generation and corresponding evidence
   are established.
5. Apply each consumer's guard, demand, and charging independently.
6. On cancellation or failure, confirm stopping and reclamation independently
   on both sides and avoid invalidating a still-trusted source result.

The typed Transfer success record binds the Transfer attempt, source and
destination Site generations, source and destination material generations and
logical views, codec and preservation rule, rows and bytes, performed
integrity checks, and retention state. It is neither consumer completion nor a
logical CID. The existing lifecycle separately owns stop and reclamation
responsibilities that remain after failure or cancellation.

Distinguish the source's original holding from the Transfer's borrowed pin. On
success, the pin may remain through destination verification, holding
acquisition, and Transfer commit. On failure or cancellation, keep it only
while source access remains unconfirmed. Release it after source access stops.
Destination cleanup that does not reference the source is not a reason to hold
the source pin. Apply existing revocation rules when corruption or a generation
replacement invalidates the source.

Do not reserve the existing source holding again for Transfer. Reserve the
peak overlap of destination construction, destination retention, and workspace.
Account transfer bytes as a cumulative quantity. Do not erase either side's
retention responsibility when the physical storage is not shared.

Each Site enforces retained-byte and execution-byte ceilings from the first
implementation. These are sub-scopes of the authoritative Run accounting, not
independent ledgers. Admission succeeds only when both the Run reservation and
the selected Site sub-scope fit. A failed admission leaves neither side
partially reserved. Existing source retention is not reserved again;
destination allocation and construction workspace are charged to the Site
where they exist. A copy at another Site is another allocation. Site
revocation alone never returns bytes whose stop or reclamation remains
unconfirmed.

A Transfer is classified by semantics, not merely by crossing a Site boundary.
Moving a completed logical value into a different material while preserving
typed values, order, and duplicate occurrences is a Transfer, including an
explicit independent copy within one Site. Filtering, derivation, and
aggregation are Compute. Sharing one immutable allocation and adding another
holding does not force a copy Transfer. A same-Site copy still accounts for
the input, destination, and workspace overlap; the required E3 end-to-end path
remains the two-Site path described above.

The in-process bounded row-wire Transfer does not compute a content digest by
default. Its initial trust boundary is the Host-adopted codec implementation
operating from a verified immutable source view into an independently owned
destination generation. Independent conformance fixtures detect value
substitution, reordering, and duplicate-occurrence loss. The typed success
record names this trust boundary and explicitly records that no physical
content digest or logical identity was established.

Other boundaries decide their integrity mechanism explicitly. Mutable input
requires a snapshot or immutability boundary that makes the verified subject
the used subject. Untrusted input requires the expected digest and its subject
to be bound to authenticated evidence. Durable storage requires integrity and
retention checks appropriate to its write/read contract. A physical digest is
neither sufficient by itself for these properties nor interchangeable with a
logical CID. Do not add a managed in-process full-data rehash where the adopted
immutable-generation contract does not require one.

Transfer success is not consumer success. Streaming unfinished rows across a
completion boundary and fusing tasks are outside this milestone.

Use a compatible representation directly within one Site. Connect file and
memory representations to common completion; add resident representations
when their implementations are ready. Do not require the Coordinator to
reconstruct every row as JSON. Keep physical manifest and chunk digests
distinct from a logical Relation CID.

The first accepted path is:

```text
checked fixed input -> existing Compute at Site A -> managed completion
  -> explicit Transfer -> Local consumer at Site B -> common completion
  -> reclamation
```

Test binding failure, corruption, foreign attempt, generation replacement,
capacity exhaustion, cancellation during Transfer, delayed stop,
destination-generation failure, one-sided cleanup failure and retry, and
multiple consumers. A completed destination generation and verification
evidence may be shared, but each consumer retains separate admission, guards,
demand, charging, and completion. Concurrent duplicate-Transfer coalescing is
outside the first implementation. Describe the result explicitly as
in-process two-Site conformance while network transport is absent.

## 6. E4: complete identity and publication integration separately

Reuse the existing obligation derivation and issuer. Add supported
implementations and publication destinations rather than rebuilding them.
Keep task success through `runCapturedInternalStrategy` distinct from formal
Program Result publication.

- Keep each checked Named Result occurrence as
  `LogicalRelation + NamedResult + BeforePublication`.
- Bind an issuer to the exact material, attempt, canonical contract,
  requirement, and deadline.
- Establish a required identity from the retained material and connect it to
  existing Artifact publication admission.
- Give a later requirement its own admission and budget. Its failure must not
  retroactively fail an earlier valid managed completion.
- Distinguish material corruption or loss of trust from an ordinary failure of
  an additional request.
- A final output CID cannot reconstruct a discarded acquisition receipt or
  convert it to the legacy observation contract.

Reject a formal publication request before execution until its integration is
implemented. Do not force an identity implementation into Local; register it
as candidate capability.

## 7. E5: remote protocol and credential grant

Build this later on E1 through E3, beginning with a subprocess or a test remote
Site. A transport replacement alone does not preserve the in-process trust
boundary. Specify adopted remote evidence, authentication, and retention before
extending the process-local profile.

Required later work includes:

- Site-originated outbound connections, mutual authentication, and validation
  of the admitted Site generation and bundle revision.
- Separation of advertisement and authority. Never expose secrets through
  discovery, logs, or diagnostics.
- Credential grants bound to tenant or principal, Connector capability,
  destination, permitted operation, task and attempt, and validity period.
- Canonical dispatch envelopes and rejection of duplicate, delayed, replayed,
  or foreign-tenant responses.
- No interpretation of timeout or disconnect as confirmed stop. Reconcile
  unconfirmed execution, retention, and cleanup after reconnect.
- Separation of Effect idempotence and unknown external outcome. Never rerun an
  Effect unconditionally because its response was lost.
- No implicit fallback from an offline self-hosted Site to Cloud.
- Runtime isolation and resource limits as responsibilities separate from
  language type safety.

The first remote acceptance should cover fixed-input Compute, retention, and
reclamation. Reject unsupported Effects before start. Durable restart, formal
Effect recovery, and production Cloud deployment remain separate milestones.
Report fake state tests, real subprocess authentication and disconnect tests,
and production placement verification separately.

## 8. Own the remaining retained-execution performance work

Maintain the performance backlog, but keep architecture extraction and
performance changes in separate commits and comparisons. Do not make them a
prerequisite for Local development.

When a Site facade is inserted into an existing same-Site path, use structural
counters to ensure it does not add unnecessary full scans, encoding or
decoding, copies, hashes, transfers, or reservations. Copies required by a new
explicit Transfer and small control metadata whose reason and size are recorded
are not prohibited. Add no new wall-clock threshold, but investigate a large,
repeatable time regression even when structural counters are unchanged.

Remaining work includes:

- Direct reuse of a managed resident relation.
- Bounded native direct output and deterministic ordinals.
- Smaller measurement indexes and removal of unnecessary re-import,
  re-encoding, and re-hashing.
- No unnecessary full-data transfer to the control side for fixed-input or
  acquisition paths.
- Formal measurement of the registered 27 cases, the 1 GiB retention limit,
  and the previously approved thresholds and comparison method.

Record a legacy capacity rejection as a rejection rather than inventing a time
ratio. Distinguish direct DuckDB, independent equal-obligation comparison, and
the product path. Compare the same retention duration, resource limit, and
verification obligations. Read the existing plan at the start and do not ask
to redefine its thresholds. Record results even when they show no improvement.

## 9. Verification and integration

For each milestone, exercise standard-entry success, failure, cancellation,
unconfirmed stop, and cleanup retry. Use normal candidate comparison and exact
registration. A test that injects an already completed candidate is not product
conformance. Distinguish test contributions from privileged fabrication of
evidence.

At one fixed SHA run the existing required gates: all three MoonBit targets,
format, public API, documentation and metadata, Core-only composition, an
independent third Connector, entries without unselected dependencies, Workers,
real DuckDB, and generator freshness. Add new tests to the default gates.
Passing all local gates defines implementation completion. Passing required
Linux CI at the same SHA defines merge readiness. Any CI fix produces a new SHA
whose required verification must be recorded again.

When integrating with the Local branch, recheck Local-only, DuckDB-only, mixed,
two-Site Transfer, required and unrequired identity, unsupported-candidate
exclusion, and full resource reclamation. After Local adopts a common API
change, run its minimal projection before expanding operation-specific E2E
coverage.

The completion report records the fixed SHA, changed boundary, implementation
matrix, counterexamples, verification scope, remaining work, performance
judgment, and CI status. Never describe E1 as remote support, E3 as durable
support, or task completion as completed Program publication.
