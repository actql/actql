# Remote Site execution

## Scope

This design extends the existing Execution Site boundary across a process or
network trust boundary. It does not create a second Run ledger or a second
definition of task success. The common MoonBit runtime owns dispatch
admission, progression, evidence acceptance, completion eligibility, retry
decisions, capacity release, and force-loss. Environment adapters perform
physical I/O and report observations to that portable control.

The complete Engine milestone contains all of the following:

1. portable common control and current Connector control logic in MoonBit;
2. the standard Local, native DuckDB, durable publication, delivery, restart,
   and cleanup path without a Node runtime; and
3. authenticated Remote Sites over loopback and separated networks, including
   direct and Store-mediated Transfer, scoped credentials, bundle operation,
   reconciliation, and reclamation.

Each item is independently testable at a fixed commit. The Engine milestone
is complete only when all three are verified.

## Ownership

The Coordinator owns execution intent, exact language-task binding, common
resource admission, accepted Remote Site evidence, and common completion. A
Site owns observations about physical execution, native settlement, retained
material, Site-local holdings, and physical cleanup. Neither journal is a
replica of the other and no distributed transaction is assumed.

MoonBit is the product authority for application decisions. A JavaScript,
native, browser, or Workers adapter may maintain physical protocol state such
as an HTTP exchange, SQLite transaction, multipart upload, buffer lifetime, or
native cancellation. It may not independently decide to reexecute a language
task, commit common completion, refund a reservation, or treat uncertain
cleanup as complete.

The first durable admission slice uses SQLite as an environment adapter. The
adapter persists an exact accepted dispatch before MoonBit permits execution.
The database enforces dispatch and task-attempt uniqueness in a transaction.
SQLite does not own the application state machine.

The Coordinator persists its exact dispatch intent in a separate journal
before starting transport. An exact retransmission reconciles that intent,
while another dispatch occurrence for the same language-task attempt is
rejected. Persisting Coordinator intent does not assert Site acceptance,
execution, evidence, or completion; those facts advance through their owning
boundaries and are reconciled separately.

## Dispatch identity and durable admission

A remote dispatch separates four identities:

- `attempt_id` identifies the language-task execution occurrence;
- `dispatch_id` identifies one dispatch of that attempt to one Site
  generation;
- `dispatch_request_cid` identifies the canonical dispatch content; and
- transport nonce and sequence values protect one communication session.

The canonical dispatch request binds the Coordinator authority, Run
Definition, exact task and attempt, target Site and generation, runtime bundle,
Connector registration and revisions, input binding, obligations, budget, and
grant. It excludes future execution results and transport nonces. Its identity
is independent of the transport encoding.

The Site journal key includes the Coordinator authority, Site identity and
generation, and dispatch occurrence. An exact request retransmission is
reconciled without additional native work. Reusing a dispatch occurrence for
different content is a collision. Reusing the task attempt for another
dispatch is not permission to reexecute it. Query, retransmission, and a new
execution attempt are distinct operations.

Cancellation is an authenticated operation on the exact dispatch occurrence,
not a retransmission and not a stop acknowledgement. The Site forwards the
request to the active physical handler, while the durable state and capacity
remain running until handler exit is observed. A non-cooperative handler enters
the existing unknown-cleanup path; cancellation alone cannot release its
reservation or authorize a replacement execution.

The accepted record is made durable before physical execution begins. A
terminal success is reported only after its required evidence, holdings, and
journal facts are durable. After restart, the Site generation changes and old
execution authority is not restored. Historical terminal facts may still be
queried, while current material availability is checked separately.

An installed execution capability additionally binds the exact Site
generation, runtime bundle, Connector registration and revision, strategy
revision, and operation grant. Unsupported requests are rejected before
durable admission. The environment runtime may invoke the registered physical
handler only after MoonBit authorizes provisioning. Provisioning, running,
native settlement, output retention, evidence, and release each use a durable
MoonBit-prepared transition; the adapter does not infer terminal success from
the handler Promise alone.

The request budget identity resolves to a pre-provisioned canonical budget
body with exact retained and execution byte ceilings. The Site admits both
ceilings atomically through the portable execution-capacity authority before
physical execution. Output retention converts only the measured bytes within
that reservation into a Site holding. Execution capacity is not returned while
native stop remains unconfirmed, and the holding is returned only after the
corresponding material cleanup succeeds.

If a handler returns before physical stop is confirmed, the durable execution
and cleanup states become unknown. The runtime retains the exact cleanup
authority and cannot release the responsibility merely because its Promise has
settled. Only a later confirmed-stop observation permits MoonBit to reconcile
the execution as failed or cancelled and then release cleanup. A missing,
malformed, or failing cleanup status remains unknown.

Status reconciliation is a separate authenticated operation, not dispatch
retransmission. Durable evidence bodies are stored with their state transition
and are re-admitted by the Coordinator through MoonBit canonicalization. A
transport JSON object or a matching string field is not accepted as evidence.

The Coordinator journal records transport uncertainty, the last exact Site
revision, and admitted evidence separately. A Site status that reports durable
evidence does not make common completion eligible unless the corresponding
canonical evidence body has been received, re-admitted, and durably associated
with that observation. A lost response advances the Coordinator observation to
unknown without inventing a Site fact. A later authenticated query may reconcile
the same dispatch. A lower Site revision, or different state at the same Site
revision, is a collision rather than a last-writer-wins update.

## Independent state planes

Execution, evidence, and cleanup are independent facts. A native operation may
be settled while its evidence is not durable. Durable evidence does not release
an output used by another consumer. Cleanup may remain unknown after either a
successful or failed execution.

Execution evidence is a typed canonical record issued only through a
Host-registered capability. The capability is scoped to the exact Site
generation, runtime bundle, Connector registration and revision, and evidence
kind. The record additionally binds the dispatch request, obligations,
retained material generation, holding evidence, and verified subject. An
arbitrary CID string is not an execution-evidence admission surface. The
registered verifier remains the trust boundary for the asserted subject; the
record identity does not turn that assertion into a proof against a malicious
implementation.

Timeout, connection loss, or Agent restart does not prove that a child process
or external operation stopped. Unknown responsibility retains its reservations
and pins. An authorized force-loss operation may end management of a Run, but
it moves the exact unreclaimed responsibility to a quarantine ledger and
isolates the affected pool. It is not ordinary cleanup and does not refund or
reuse physical capacity. Late exact cleanup evidence may resolve the old
responsibility without reviving a failed Run or completion.

## Transport and authentication

The initial control candidate is authenticated outbound HTTPS. The selection
is not a requirement to invent an ActQL framing protocol. Mature TLS, HTTP,
cryptography, and SQLite libraries are used through thin environment adapters.
The integration slice must measure polling delay, connection count, idle cost,
and cancellation behavior before the transport choice is finalized.

The required Remote Site tests cover an authenticated loopback subprocess and
separated native Site networks. They use distinct Store roots and may not use
shared memory, a shared filesystem, or a shared absolute path as the data
channel. Authentication binds the adopted runtime, issuer, capability, Site
generation, attempt, and operation. A valid Site signature authenticates a
registered assertion; it does not prove arbitrary computation is correct.

Application signatures are required when a record crosses a trust boundary or
must be independently verified. Durability alone does not require a separate
signature. Record type and version provide domain separation. The receiver
accepts only configured suites, keys, and scopes.

## Transfer routes

Transfer is an explicit managed operation and not a language task. Both direct
Site-to-Site streaming and outbound-only Store-mediated transfer are required.
Candidate admission checks route reachability, receiving capability,
authorization, bounded capacity, and known cost before starting.

The direct route streams bounded batches between reachable Sites. The
Coordinator provides exact connection and grant facts but does not receive the
bulk bytes. The Store route uses separate upload and download grants. A sealed
object may be reused by a newly admitted download attempt without uploading the
source again. Object state, individual use attempts, integrity, and cleanup are
separate state planes.

Both routes bind an ordered chunk manifest, count, codec, schema, logical view,
source material generation, source and destination Site generations, Transfer
attempt, capacity, and expiry. Physical digest validation is distinct from the
logical Result CID. Digests are computed while streaming or reused from the
same verified immutable encoding; validation must not add an unconditional
full reread.

The source pin follows actual source access. Once source access has stopped,
destination cleanup cannot prolong that pin if it no longer refers to the
source. Destination holding and cleanup remain independently accountable.

## Publication, credentials, and bundles

A Site may stream a checked Result occurrence directly to the Publication
Store. The Coordinator is not a bulk relay. Publication still requires
registered evidence connecting the occurrence, logical view, canonicalization
contract, and logical CID. A physical digest alone cannot establish the logical
Result.

Transfer and Publication may share an immutable physical allocation only with
independent holdings and compatible retention policies. Releasing either use
must not remove the other. Shared bytes are charged once; independent copies
are separate allocations.

Credentials are resolved at the Site behind a scoped operation surface. A
grant binds principal, tenant, environment, Site generation, Connector and
runtime revisions, resource origin, operation, Run, attempt, dispatch, expiry,
revocation, and use ceiling. Raw secrets are not placed in the wire journal or
a generic environment map. Redirects are reauthorized and do not receive a
credential unless the target is admitted. A durable use claim is not refunded
when a crash makes pre-send use uncertain.

Runtime bundles support package, signature verification, installation,
activation, drain, rollback, and reclamation through standard operations. The
verified component is bound to the loaded component. Old code is retained
while execution, readers, or cleanup require it; historical verification keeps
the manifest, signature, and required decoder rather than every old executable.
OCI and existing signing tools are candidates, not semantic requirements.

## Environment adapters and completion evidence

Environment-specific code is justified for physical capabilities: TLS and
HTTP, filesystem synchronization, conditional Store commit, SQLite access,
native DuckDB calls, OS process control, and secret-provider access. The
portable control consumes bounded observations from these adapters. It does
not require full rows or cells to cross the language boundary merely to share a
control decision.

Migration is complete only when existing product call sites use the MoonBit
control and the superseded JavaScript decision code is removed. Temporary
duplication must name its removal condition. Independent fixtures remain, but
two product state machines are not retained as mutual tests.
