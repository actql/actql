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

Common managed completion requires the Coordinator journal to contain the
exact durable managed-output observation. The admitted evidence, subject, and
measurement identities must match the remote dispatch and the current material
handle before the ordinary Host task commit can run. Site-issued evidence on
its own cannot commit a DAG output, even when its signature and physical
subject are otherwise valid.

## Projecting an existing source-free Run

### Original Effect request context

Effect materials may carry `client_request_identity`, a bounded string encoding
the existing seven-component Client request record. The Effect issuer accepts
only an existing request Owner matching the checked Program, parameters and
caller input intent. Admission revalidates its logical scope and intent CIDs;
it does not choose another caller, issue a new Run or refresh authorization.
The existing Run-materials version and identity domains remain unchanged. A
body carrying this context has different bytes from one without it.

Before Source I/O or a consumer receiver borrow, the Native connection checks
that this context matches the dispatch Run and authority scope. The consumer
also compares it with the producer's original envelope retained in the existing
Site journal, including when reconciling a completed consumer. A separately
valid request for another caller cannot replace the producer's request.

Missing request context stays absent and cannot supply an Effect Preview or
approval dispatch key. Current Provider observe, approval and write authority
remain separate checks. Ordinary Effect-free issuers omit this field and keep
their existing encoded bytes.

### Effect-free materials

`@actql/run-host-core.issueSourceFreeRunMaterials(prepared, compilation,
admission, definition, retained)` projects an existing source-free, effect-free
JSON Values Run into `actql-remote-run-materials/0.1`. `retained` contains the
original document, optional parameter body, admitted environment owner and its
original wire body. The existing Run binding verifies the compilation,
admission and definition. Ordinary bounded input checking verifies the retained
Program and parameter identities against that preparation; it does not compile
a new executable Plan, issue authorization, or issue a new Run definition.

Run identity, scope, creation and expiration times come from the admitted
definition. Prepared invocation and authorization come from the admitted Run
evidence. Callers cannot override these fields. The issuer does not extend or
refresh expiry; the Site must still verify current authority and lifetime at
receipt and physical start. Receiving Site admission reconstructs the Plan with
its existing checker/compiler and matches the original Run definition CID;
matching identity alone is not execution permission.

The encoded inner body is bounded to 262144 UTF-8 bytes, including JSON quoting.
Program, parameters and environment retain their existing 65536-byte bounds;
passing those individual checks does not exempt the aggregate wire limit. The
existing `pollDispatchMaterialsJson` issuer wraps this body without changing the
Connector input binding or the dispatch identity domain. No wire version, CID
preimage, stored data or authorization contract changes are required.

This projection does not supply response-loss recovery, handout cancellation,
restart execution permission, or repair missing Output by recomputation. Those
remain separate from Run identity admission and physical resource release.

## Dispatch identity and durable admission

A remote dispatch separates four identities:

- `attempt_id` identifies the language-task execution occurrence;
- `dispatch_id` identifies one dispatch of that attempt to one Site
  generation;
- `dispatch_request_cid` identifies the canonical dispatch content; and
- transport nonce and sequence values protect one communication session.

The canonical dispatch request binds the Coordinator authority, Run
Definition (`run_definition_cid` is always the `actql-run-definition/0.1`
CID, never a Program definition CID), exact task and attempt, target Site and generation, runtime bundle,
Connector registration and revisions, input binding, obligations, budget, and
grant. It excludes future execution results and transport nonces. Its identity
is independent of the transport encoding.

The input binding is a bounded canonical Connector control document. The
Coordinator sends its exact body with the dispatch, and the Site recomputes its
identity before durable acceptance or physical execution. A retransmission may
reuse the same dispatch only with the same binding body. The control document
does not carry bulk relation bytes: those remain subject to the direct or
Store-mediated Transfer contracts.

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

### Durable cancellation before Site admission

`actql-remote-poll-cancel/0.1` carries the original canonical request and its
exact CID, without materials or execution authority. Site authentication and
current delegation checks precede journal mutation. The operation binds the
Coordinator authority, Run, task attempt, dispatch, Site generation, runtime,
and grant already present in that request; a request ID alone is insufficient.

The existing Site journal persists the cancellation intent. For an absent
attempt, cancellation admission installs a nonstartable `ExecutionCancelled`
record with `CleanupReleased` inside the same fenced transaction that excludes
start claims. No resources were acquired for that absent record. A transient
not-seen response cannot establish this durable prohibition. Failed or uncertain
persistence returns no terminal success; an exact retry reconciles the saved
record without another attempt or resource return.

For a previously accepted attempt, cancellation and the exclusive start claim
race in that journal. Only cancellation winning the unclaimed Accepted state
may confirm cancellation before physical execution. Cleanup remains active.
After start, saving cancellation intent does not confirm physical stop or
cleanup; the existing physical stop and cleanup owners retain that obligation.
A completed execution disposition and its evidence are never rewritten to
unexecuted by a later cancellation.

The attempt index and exact request-CID collision checks retain cancellation
records across process reconstruction. There is no cancellation-specific record
retirement. A future retirement must preserve the existing generation/lifetime
and replay exclusion; deleting a cancellation must never revive an old dispatch.

The accepted record is made durable before physical execution begins. A
terminal success is reported only after its required evidence, holdings, and
journal facts are durable. After restart, the Site generation changes and old
execution authority is not restored. Historical terminal facts may still be
queried, while current material availability is checked separately.

The durable start boundary has five conceptual cases, represented by the
portable record and custody state rather than an adapter-local state machine:

| Conceptual case | Portable representation | Replay rule |
| --- | --- | --- |
| Accepted, not started | `Accepted`, no operation custody | Resume the same occurrence through the durable start sequence; do not create another occurrence |
| Start owned | `Provisioning`, bundle custody and optionally operation custody | Continue the same occurrence only |
| Running | `Running`, exact operation custody | Exact replay reconciles; it never starts a second handler |
| Failed before start | `Accepted` followed by durable release or cancellation | No physical stop is fabricated |
| Unknown after start | `ExecutionUnknown` with cleanup custody | Keep reservation and owner until exact stop and cleanup are confirmed |

The ordering is durable acceptance, durable provisioning, physical operation
ownership, durable running, then handler invocation. A synchronous failure
before operation ownership follows the before-start release path. A failure
after ownership without a confirmed stop becomes unknown. A crash or lost reply
does not turn an existing nonterminal record into permission to restart it.

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
with that observation. A lost transport response advances the Coordinator
observation to unknown without inventing a Site fact. A semantic refusal or
failed/unknown observation commit does not manufacture another transport
transition. A later authenticated query may reconcile the same dispatch.

### Exact dispatch recovery after response loss

The Coordinator must retain the original dispatch, Connector binding and any
Run materials together before the initial delivery. The existing poll owner
checks the dispatch/binding identity and canonical envelope. The retained Run
owners separately check that the materials were projected from that original
Run; the envelope's CID or syntax is not a Run authorization decision. No
expiry, authorization evidence, input or Run identity is reissued on recovery.

The Node Coordinator's recovery-enabled installation supplies
`currentDispatchContext(dispatch, envelope)`: a synchronous, trusted Host
projection from those retained Run/configuration/authorization owners. It must
verify the original association and current Run/authorization lifetime, Site
binding and cancellation facts, not copy claims from the envelope or a query
reply. The ordinary activation authorization gate also runs again. Initial
delivery checks this projection before persistence and again after its commit;
recovery checks it after the query/authorization awaits immediately before
transport. Missing installation does not opt a legacy transport into R2.

| Durable observation at recovery | Current exact query | Common owner decision |
| --- | --- | --- |
| No Site observation | Admitted `not seen` for this request | May redeliver the retained envelope if current checks allow |
| No Site observation | Timeout, missing reply or other transport/storage failure | Unknown; no automatic send |
| Accepted, no start/evidence/cleanup fact | Accepted, or an already-admitted Accepted replay | May redeliver the same occurrence if current checks allow |
| Start/provisioning, running or terminal observed | Any admitted old Accepted replay | Reconcile; never restore Accepted or grant another start |
| Any Site observation | `not seen` | Does not erase durable history or authorize a send |
| Any observation | Different identity, stale unadmitted observation or contradictory body | Typed refusal; no replacement attempt |

Accepted is a historical observation, not an unstarted lease. A Site receiving
the same delivery uses its existing admission, queue deduplication, executor
slot and durable start claim. It may queue the existing Accepted occurrence;
if start won between query and arrival it only acknowledges the current record.
`AlreadyMine` is confirmation of a saved claim, never independent permission
for a new process to enter the executor. A resident holder has a fresh claimant
and uses the existing startable-record/runtime-custody checks. Recovery does not
construct a second execution state machine.

The Node SQLite journal retains delivery bytes in the additive
`dispatch_deliveries` table, with a foreign key to the exact dispatch intent and
the `dispatch_delivery = actql-remote-coordinator-delivery/0.1` capability. The
initial intent and delivery are inserted in the same SQLite transaction. A
failed/unknown commit gives no send permission; reconstruct the Coordinator
from the durable journal before attempting recovery. An existing dispatch with
different envelope bytes is `RemoteDispatchDeliveryMaterialsCollision`.

The history-journal/record and public wire formats remain 0.1 and their canonical
bodies/CIDs are unchanged. R1-compatible journals without this capability stay
openable: initializing the additive empty table does not manufacture delivery
bytes or rewrite their observation records. Their query, evidence and cleanup
remain usable; `RemoteDispatchDeliveryMaterialsMissing` refuses only automatic
redelivery. Never attach newly generated materials to such an old intent.
Pre-R1 journals retain the separate history-required refusal described below.

### Output report custody and acknowledgement

An Output-result report is a durable observation separate from publication,
physical release, and execution completion. Before the Site sends the report,
its existing journal stores the canonical report bytes and the exact
Run/dispatch/attempt/Output-bound inputs. The report CID is not replaced by a
new attempt or regenerated after a response loss. The journal performs a
preflight size check against its configured record limit before payload or
Transfer side effects begin.

The receiver responds only with the typed
`actql-remote-output-report-reply/0.1` envelope. `accepted` is emitted only
after the receiver's existing Output owner durably admits the exact report;
replaying the same report returns the saved acceptance fact without a new
revision or delivery. Empty bodies, legacy `200`/`accepted: true`, unknown
responses, and another report's CID are not acknowledgements. A checked
refusal is one of the allowlisted typed reasons and remains a durable attention
state until an explicit retry rechecks current authority and scope.

The Site validates the typed ACK against the saved report, commits that reply
in the same existing journal owner, and only then closes report-pending state.
Transport failure or an uncertain ACK commit leaves the report pending with
bounded retry state. On control-process startup, unacknowledged reports are
enumerated from the journal; a holder queue or an in-memory CID is not a
recovery source. Physical payload release may precede ACK, but it never stands
in for ACK and does not authorize recomputation or a second executor entry.

The current Output-report implementation retains one immutable snapshot slot per Output
intent and bounds the set to 32 slots. Duplicate ACKs, retries, and cleanup do
not allocate additional history. This is an Output-report retention bound, not the global
history-limit proof for later O5/O2/O6 work.

There is at most one delivery per dispatch, bounded by `maxDispatches`. The
encoded envelope bound is 1,442,816 UTF-8 bytes, matching the existing poll
materials encoder (1,179,648 + 262,144 + 1,024); `maxDeliveryBytes` can impose a
smaller deployment bound. Inner materials retain their 262,144-byte cap, and
binding/quoting retain the existing poll-owner bounds. The resident HTTP default
is 1,441,792 bytes and its journal defaults to 1,048,576 bytes per record; a Host
targeting that configuration must select the tighter 1,048,576-byte delivery
cap. Those transport/storage limits do not enlarge the common encoder limit.
Over-limit envelopes are refused before initial delivery. No unbounded history
or automatic retry loop is added; one recovery step queries then reconciles or
delivers the exact saved bytes once. A retained gateway offer remains transport
custody, not proof of start permission. O2 cancellation and O6 generation/restart
completion remain separate units.

### Durable observation replay

The existing Coordinator owner records the typed state and the evidence
identities actually supplied by each admitted observation, atomically with its
state update. This is not a transport pending queue or a CID-only receipt.
Current authentication and the expected authority, Run, dispatch, Site and
generation binding remain necessary on every request, including a replay.

A recorded exact observation is ACK-only: it does not increase the Coordinator
revision, restore an earlier Site state, confer execution permission or issue a
new dispatch. An unadmitted lower Site revision is refused. Different state at
the same position, or replacement of an accepted evidence identity, is a
collision. Reply/status is not an independent receipt namespace. The existing
typed owner may monotonically supplement missing execution evidence, or the
complete managed-output evidence/subject/measurement profile, at a known
position without restoring that position's availability or cleanup state.

Ordinary admission permits 64 distinct Site revision positions per dispatch.
After exhaustion, a new position requires an as-yet unseen closing fact:

| Closing fact or evidence slot | Consumed by | Retry/replay |
| --- | --- | --- |
| Terminal execution disposition | Settled, failed or cancelled | Cannot replace another terminal disposition |
| Final evidence disposition | Durable or rejected evidence | Cannot replace another final disposition |
| Management loss | Force-lost or recovered-after-loss custody | Repeated loss consumes no new slot |
| Confirmed physical reclaim | Released/recovered-after-loss with no material or quarantine | Cleanup attempts alone do not consume it |
| Execution-evidence identity | First typed admitted evidence CID | Filled identity is immutable |
| Managed subject identity | First typed admitted subject CID | Filled identity is immutable |
| Managed measurement identity | First typed admitted measurement CID | Filled identity is immutable |

These are seven finite facts/slots, not a budget of retry revisions. Every
position has at most three existing evidence profiles (none, execution evidence
only, or the complete managed triple), so at most 71 positions and 213 profiles
can be retained. The canonical history is limited to 131,072 UTF-8 bytes, 4,096
JSON nodes and depth 3. Exact accepted replay allocates no slot. A retry-only
new revision after ordinary exhaustion is refused without changing either
state or history; Site physical stop/cleanup remains independent and its final
facts can still be admitted. No admission failure authorizes force-loss,
capacity refund or re-execution. These bounds do not prove a bound on every
Site `prepare_*` transition or complete O5/O2/O6 history.

For managed completion, physical reclaim alone does not close evidence
admission. The final evidence disposition and the required typed final profile
must also be received. Generic evidence-only completion requires its admitted
execution evidence, not a managed subject/measurement it cannot supply. The
required profile is derived from the admitted typed evidence body, never a
sender's transport-kind hint. Once admission is closed, existing exact receipts
remain replayable. Another of the three bounded profiles at an already admitted
position may arrive in reverse order, but no new position is admitted and no
observation can undo physical reclaim or resurrect output.

The wire observation contracts remain 0.1. History-bearing persistent records
use the distinguishable `actql-remote-coordinator-history-record/0.1`, and the
Node journal uses `actql-remote-coordinator-history-journal/0.1`. An old
Coordinator journal cannot provide R1 replay guarantees and is refused with
`CoordinatorJournalObservationHistoryRequired`; an old canonical record is
refused with `ObservationHistoryRequired`. Historical admissions are never
invented from its latest state or accumulated evidence. Refusal preserves the
original DB, WAL and unfinished cleanup custody; it is not cancellation,
reclaim, failure confirmation, or permission to resend work. No automatic
migration is provided.

An operator retaining an old journal must use a separately pinned matching
implementation, rather than deleting its root or asking the new writer to
invent receipts. With the same configured authority, the old owner recovers
the exact dispatch and its outstanding custody, then reconciles and releases
it using that version's ordinary rules. Returning to the new writer requires
a separate empty root; rejection alone never terminates the old obligation.
The fixed-baseline compatibility check in
`scripts/test-coordinator-legacy-custody.mjs` verifies old-owner continuation
after a DB+WAL/no-SHM refusal, and that the old writer rejects the new format
without changing its logical state/history. This is Coordinator custody
evidence, not a claim that replaying a release observation proves physical Site
cleanup. Site physical release requires its normal independent evidence.

Before opening an unclassified Node database normally, the adapter inspects a
private DB+WAL snapshot using read-only source descriptors, retaining file
identity and rejecting changes during inspection. SQLite never opens the
unsupported source itself. A classification failure and an isolated database
close failure preserve separate causes and a retryable cleanup owner. Retrying
that owner only releases the inspection resources; it does not reclassify or
initialize the original journal.

The native Coordinator applies the same boundary with a pinned read-only
DB+WAL copy. It checks the SQLite schema and re-admits every Coordinator record
through the existing typed owner before opening the source normally. Authority
comes from the caller-owned Coordinator, not from the stored record. It neither
initializes nor migrates the source during inspection. Failed inspection and
failed release of the isolated database preserve separate typed causes in
`InitializationCleanupPending` and a `CoordinatorInitializationCleanup` owner.
Its `retry()` is cleanup-only; `pending()` becomes false only after both SQLite
and the private copy are released. A successful retry does not retry admission.

An outbound gateway connected to the Coordinator's observation receiver waits
for durable admission before ACK or waiter resolution. A receiver may reconcile
an exact accepted replay even with no pending waiter, including after restart.
Failed/unknown storage returns a retryable failure rather than a successful
ACK. A transport-only gateway without that receiver does not offer R1 durable
ACK guarantees.

## Independent state planes

Execution, evidence, and cleanup are independent facts. A native operation may
be settled while its evidence is not durable. Durable evidence does not release
an output used by another consumer. Cleanup may remain unknown after either a
successful or failed execution.

The Coordinator's checked task observation also retains an admitted final
evidence rejection. The Run projection treats that rejection as task failure
and stops selecting new tasks; it does not rewrite `NativeSettled` into a
physical execution failure. Settled execution with evidence still pending
remains unpublished and unresolved. Physical release is projected only from
the independent cleanup observation, including after evidence rejection.

Execution evidence is a typed canonical record issued only through a
Host-registered capability. The capability is scoped to the exact Site
generation, runtime bundle, Connector registration and revision, and evidence
kind. The record additionally binds the dispatch request, obligations,
retained material generation, holding evidence, and verified subject. An
arbitrary CID string is not an execution-evidence admission surface. The
registered verifier remains the trust boundary for the asserted subject; the
record identity does not turn that assertion into a proof against a malicious
implementation.

Holding evidence is derived by the common runtime only after it acquires the
exact Site holding. Its canonical identity binds the dispatch occurrence, Site
generation, material generation, and retained byte charge. A physical executor
may report immutable output facts, but it cannot choose this authority binding.

Timeout, connection loss, or Agent restart does not prove that a child process
or external operation stopped. Unknown responsibility retains its reservations
and pins. An authorized force-loss operation may end management of a Run, but
it moves the exact unreclaimed responsibility to a quarantine ledger and
isolates the affected pool. It is not ordinary cleanup and does not refund or
reuse physical capacity. Late exact cleanup evidence may resolve the old
responsibility without reviving a failed Run or completion.

### Cleanup during interrupted completed restoration

A completed Native holder may lose use authority while reconstructing its
original resources. The adopted cleanup handoff separates permission to expose
output from verified exclusive physical custody. Initial restoration still
requires the current Site, admitted completion, original input binding and
current authority. The Runtime then retains one owner and its initial file
custody, evidence, material generation and Source observation through retry.
No retry substitutes another occurrence or reacquires Source/execution.

The existing ExecutionSite accounting owner prepares one opaque historical
holding token at that authorized boundary. A pending token owns a real cleanup
responsibility but reserves no bytes, so capacity rejection cannot make Site
teardown appear clean. Under the same verified exclusive custody, successful
consumption transfers that responsibility into one real holding for the original
byte count, subject to the unchanged held-plus-reserved capacity ceiling. This
cleanup accounting may complete after Site revocation; the token cannot be
consumed twice or abandoned to erase the obligation. Normal holding, operation
and read admission retain their existing revocation guards.

Already-owned pending restoration reconciles only monotone completed cleanup
progress before physical I/O. Releasing or unknown cleanup and loss of use
authority enter the exact cleanup-only path. Foreign, regressed, terminal,
changed-material and quarantined records remain refused. Physical release must
succeed and exclusive custody must still hold before returning Site capacity or
bundle ownership. Root-open or unlink/sync failure retains the same callback;
a retry may reconstruct only the original cleanup handle and must preserve a
foreign replacement. Loss of exclusive custody retains responsibility.

This extends cleanup accounting within the existing owner. It changes no wire
identity, execution evidence, generation-restart authority or release contract.

### Single-input retained task chains

The Native resident profile admits one Source acquisition followed by checked
single-input tasks and one terminal Named Result. Each dependent task consumes
the immediately preceding task's output; any control dependency must name that
same predecessor. Fan-out, fan-in, multiple acquisitions and multiple terminal
Results require additional composition and remain refused
by this profile; the common checked graph retains its broader capabilities.

An intermediate task uses its predecessor's typed completed output, not the
original Source capture preparation. The physical strategy Owner keeps the
original checked graph and an execution view containing that predecessor and
consumer. The view maps local execution coordinates back to original task,
input-producer and control-predecessor coordinates. Original task references,
policy consultation, generated-sequence selection, output generation and Result
ownership continue to use those original coordinates. Imported row and verified
wire-byte statistics describe the completed predecessor and do not manufacture
a Source observation or completed ancestor tasks.

The consumer's file-backed output becomes independent only after the exact
file generation and output evidence are durably committed. The Runtime then
retires the original Compute export and confirms existing Run cleanup before
returning the incoming reader and receiver capacity. Cleanup failure keeps the
same responsibility available for retry. Ordinary output reads may use the
committed file while retirement is pending, but the next retained manifest
handoff waits for confirmed input cleanup. Resource ceilings and logical work
are unchanged.

The resident holder explicitly supplies this retirement responsibility.
Direct executor callers that do not supply it keep their existing input-borrow
lifetime through Runtime release, while still requiring durable output files.
Generic failure cleanup before commitment cannot invoke receiver retirement.

A holder indexes execution, outgoing handoff, successor and output cleanup by
exact dispatch identity. Retransmission selects the same occurrence and cannot
replace its successor or revive an input borrow. Cleanup proceeds from child
to parent; an early parent release remains pending until its child is safe.
Output reports are durably handed off before physical output cleanup.

After a middle holder stops, restoration uses the original completed evidence,
file custody, consumer component holding and saved incoming binding. It neither
reacquires Source nor re-enters Compute. Historical cleanup-address admission
belongs to the common retained-input cleanup Owner. A checked route identifies
the original edge, while durable producer evidence and the consumer's accepted
record bind the exact reader responsibility. Accepted, failed, cancelled and
release-retry states grant cleanup addresses without granting use or execution.
The physical caller must still establish exclusive stop and current Site scope.
Only an exact absent reader key can mean that an accepted occurrence never
borrowed; the original Transfer and receipt must exist. Other readers continue
to fence receiver reclamation. File cleanup and formal task release remain
separate responsibilities and cannot be inferred from returning this reader.


## Transport and authentication

The initial control candidate is authenticated outbound HTTPS. The selection
is not a requirement to invent an ActQL framing protocol. Mature TLS, HTTP,
cryptography, and SQLite libraries are used through thin environment adapters.
The integration slice must measure polling delay, connection count, idle cost,
and cancellation behavior before the transport choice is finalized.

The Coordinator-side outbound gateway is a physical HTTPS adapter. It queues
an already admitted canonical dispatch for one exact Site generation and
returns only MoonBit-generated envelopes. The authenticated Site polls that
endpoint and posts a MoonBit-generated observation after making its own
admission durable. The gateway does not grant execution, infer completion, or
choose whether a task may be retried. A disconnected waiter leaves the exact
dispatch available for reconciliation instead of silently authorizing a new
execution occurrence.

Dispatch delivery, status reconciliation, and retained-output release use
distinct canonical poll operations. A query asks the Site journal for the
exact durable observation and may return `not seen`; it never reaches dispatch
admission or native start. A release may advance only the exact existing
output owner and reports the resulting durable cleanup state. It cannot admit
or re-execute work. Only an explicit dispatch operation may deliver or
retransmit executable work. Cancellation before gateway admission creates no
pending operation, while a caller disconnect after admission removes only
that caller's waiter.

An ordinary status can arrive after a Release waiter is registered, including
from another control process's earlier query. It is admitted as an observation
without retiring Release delivery. The gateway keeps offering the same Release
until the existing Owner confirms terminal execution and released cleanup,
without retained material or quarantine. With a durable receiver, that decision
uses its latest committed observation rather than an older reply. This delivery
fence neither cancels the Run nor grants another execution.

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

Runtime bundle trust separates historical verification from authority for a
new install. Normal key rotation may keep an old public key as
verification-only while enabling a replacement key for new bundles. A key
compromise response may remove the key entirely, but the resulting inability
to reopen records signed only by that key is not silently converted into
successful verification. Durable catalog membership records prior acceptance;
signature validity by itself does not prove that an artifact was issued before
a later compromise or revocation event.

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

The native Store route uses the same portable request, reply, lifecycle, and
receipt owners as the Node route. Its HTTPS adapter sends or receives one
admitted physical chunk per bounded operation. The source-side journal records
the sealed Store object before releasing source access. The destination first
reserves aggregate capacity, installs independently owned file generations,
and durably records the exact destination receipt before asking the Transfer
Store to complete the reader occurrence. A restart verifies the retained file
generations and receipt instead of uploading or downloading the payload again.
The filesystem and SQLite adapters report physical results; they do not decide
Transfer completion.

The common Transfer record is persisted as one canonical body containing the
re-admitted request, physical manifest, and independent attempt, object,
integrity, and cleanup states. Its journal key identifies the Transfer
occurrence rather than its content, so retransmission can return the existing
record while different content for the same occurrence is rejected. Native
SQLite performs only transactional insert, compare-and-swap, and recovery;
MoonBit remains the sole authority for valid state combinations.

Direct Transfer admission envelopes and state replies are emitted and
re-admitted by the same MoonBit owner. The Node receiver and native HTTPS
client therefore share one request and lifecycle interpretation. The native
client validates every admitted chunk length and digest before physical I/O,
sends one bounded chunk per request, and never joins the Result into one bulk
buffer. HTTPS, mTLS, response bounds, and physical cancellation remain adapter
operations. A destination commit response becomes usable only after common
state admission confirms the exact request and committed state.
The native direct path durably accepts the occurrence and records start before
network I/O. Source settlement and destination commit then advance through
SQLite compare-and-swap. Reopening the journal returns an already committed
occurrence without sending the payload again; an interrupted copying state
retains its responsibility and retries only the same admitted occurrence.

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
grant binds principal, namespace, environment, Site generation, Connector and
runtime revisions, resource origin, operation, Run, attempt, dispatch, expiry,
revocation, and use ceiling. Raw secrets are not placed in the wire journal or
a generic environment map. Redirects are reauthorized and do not receive a
credential unless the target is admitted. A durable use claim is not refunded
when a crash makes pre-send use uncertain.

### Original installation metadata preparation

Some declared Sources need an explicitly selected metadata observation before
their final relational schema exists. This is not a business Program Run and
cannot borrow a query grant or a fictitious future Run allocation. The existing
Host installation/acquisition and Credential Owners retain the actual trusted
publication request, actor/Account, Site/profile generation, runtime/Connector,
credential material, resolver and dependent metadata occurrence. A pure subject
constructor, a named connection or an equal public CID cannot recreate them.

The [closed preparation alternative](../spec/protocols/contracts.md#installation-metadata-preparation)
records only actual supplied subject DATA. In particular,
`declaration_source_cid` identifies the exact retained declaration UTF-8 source
bytes, not a semantic Contract or authority. Missing adoption, authority or
credential originals are not filled by hashing current configuration under
new names. Actual opaque Host/request/Site/credential references and current
checks remain separate. The old Run and Native Local preparation alternatives
keep their existing strict scope and bytes.

Database and dependent schema retrieval have separate original grants/uses.
The dependent target is selected by Common from the actual declaration and
database observation, not by name, first position, compatible schema or a
predicted string. Each operation retains the exact occurrence, GET path,
origin and empty body, plus current Account/issuer/material/egress and a
confirmed same-journal use claim before I/O. The physical Site privately
retains its actual namespace/environment and original control/journal/resolver;
subject DATA is not their replacement. Query/property reads still use their
own actual Run-bound authority.

The original acquisition/resource supplier covers all simultaneous request,
response, source snapshot, decode/contract-construction, observation, callback
and cleanup holding. Parser bounds are not funding. Missing real authority,
context or funding remains Unavailable. Publication and Run adoption retain
the observed originals and generation correspondence; restore does not
rediscover schema or renew authority. Cold grant/use admission restores DATA
only, never a live request or permission to resend an Unknown operation.

The installed Row Credential Site accepts this alternative through its existing
publication custody. It retains the actual Host request and checked-profile
pair, original declaration alongside its source CID, Account gate and captured
methods/receiver, original Site/profile facts, issuer/key and SQLite Journal.
Each registered metadata occurrence retains its original selected target,
Common Scope, Account decision, signed grant or first failure before the first
fallible await. A dependent target must be issued by the original declaration's
selection owner. Its projection is DATA, not Account authorization. Duplicate
occurrences cannot issue another grant, and observed Account/profile failure
does not revive when equal configuration is put back.

Before signing, the Site checks the bounded Host-profile observation, actual
Site current callback and original Account configuration/decision. It repeats
the synchronous fences after signing and supplies the existing private HTTPS
binding with those same originals; the binding retains secret material rather
than disclosing it to the Connector. Every physical use still needs its own
exact Scope, current authorization and confirmed same-Journal claim. This
issuer port does not perform metadata I/O, supply egress or reserve resources.

The new purpose requires the Journal's immutable original method surface.
Admission failure returns the existing initialization cleanup Owner with the
same Site/Journal responsibility. Cleanup closes the private binding before
the captured original Journal close/receiver and retires the Common aliases
only after their acknowledgements. A thrown close, missing method or nonboolean
return keeps the same duty pending; a completed original close is not repeated.
The legacy Run Site retains its existing signing and close behavior.

The simultaneous preparation inventory includes bounded issuer PEM bytes and
decoded text, the original private/public KeyObjects, optional bounded ASCII
CA text, Host/profile/Account observations, the metadata view's aliases,
captured callbacks/receivers, the explicitly bounded occurrence inventory and
its target/Scope/decision/grant/failure references, SQLite state and private
secret binding. Closing aliases does not reclaim escaped grants, persisted
Unknowns, response observations or failed cleanup state. These bounded inputs
and reference-retirement rules are not a numerical funding profile.

The private Node metadata view captures the selected Common callbacks and
their original receiver once. It owns opaque Subject, Scope, Grant, Use and
SignatureEnvelope aliases; copied or foreign-view values cannot cross it.
`forSubject` returns a stable control for that same original subject, not a
control reconstructed from its CID. It selects `installation-metadata`
explicitly, and its named grant projection is distinct from the old seventeen
Run fields. The eleven subject and six request fields, their typed constructor
arguments and field projections are generated together from the existing
Common declarations. Common owns decoding, canonical bytes, identities and
scope matching; JavaScript does not rebuild their preimages.

The view performs no asynchronous work, authentication or durable claim.
The existing physical signer can use its transport-neutral signature methods
only with independently supplied actual authority and key material. Retiring
the view cuts its own six maps' original-value references, not a physical
request, original key/use/Unknown responsibility, journal claim or escaped
wire bytes. Captured callbacks/receiver and returned closures remain live for
their actual escaped lifetime; WeakMap/retirement/GC is not a byte refund or
cleanup acknowledgement. An operational installer must independently retain
the original Host publication request and its before/after-await current
authority, actual Site/profile/control/journal/resolver and resource supplier.

The explicit installed Source publication call issues its own process-local
opaque request before its first profile-read await. The Host then binds the
original root, actor, Common runtime, selected Connector entry, checked profile,
runtime binding and secret-resolver reference once. A copied token, equal
configuration, rechecked profile copy or another publication is not that
request. Its original UUID is only a lookup coordinate for the preparation
subject, never an authority or a cold operational reconstruction.

`observeInstalledSourcePublicationCurrent` re-reads the selected bounded Host
profile and compares its exact parsed original values without normalization or
a new identity domain. An observed replacement or read failure closes new
operation admission even if equal bytes are subsequently put back. The
synchronous original-pair assertion follows awaited physical Site, Account,
egress and resource checks immediately before the original claim/send; it is
not a substitute for any of them. The same barriers apply after response
awaits, before disclosure, metadata admission and publication. The Connector
keeps its own exact declaration/source bytes, selected observation and original
Contracts; this Host fence neither supplies them nor re-resolves them.

Publication completion, failure and abort close new-operation admission. A
failure with pending child cleanup retains that same request and all original
references behind the existing Host reference finalizer. Only the captured
original child status and retry can complete that duty; no replacement status,
new publication, repeated metadata I/O or Promise settlement is an ACK. A
retiring request can still project its original lookup coordinate for cleanup
but cannot authorize another send. Reference retirement is not physical
release, numerical funding or permission. Existing installers that do not
consume this private seam retain their former publication behavior.

### Original authentication dependencies

A registered Google service-account dependency uses a separate existing
credential grant/use for `https://oauth2.googleapis.com`, `POST /token` and the
`application/x-www-form-urlencoded` body. It never changes the API grant's
origin or operation. Both grants retain the same issuer, principal, namespace,
environment, Site/generation, runtime/Connector, Run, attempt and original
dispatch. The authentication deadline cannot extend either original grant.
No additional dispatch identity is inferred from the assertion or token.

The Credential Owner's private `CredentialAuthenticationRequest[Material]`
retains the original parent use, authentication grant and actual supplier
material. It checks the explicit byte ceiling before hashing the actual form
bytes, retaining only their private digest and length. The separately claimed
authentication use must retain that exact grant object. The resulting operation
and every later check require the same request, parent use, authentication use
and material references; re-admitted equal JSON/CIDs cannot replace them. There
is no public body/hash projection or serialized reconstruction of this pair.

This is correspondence, not issuance or a new permission plane. The installed
Credential supplier must admit the real material's membership and selected
service-account, delegated subject, exact scopes, key generation and assertion
expiry. An external reference, `kid`, Site generation or equal native key does
not prove those facts. Missing original material remains unavailable. Current
authority/signature, the existing journal's original claim and use ordinal,
and final sign/send authorization remain independent requirements, checked
again after awaits. Token issuance is not API authorization. An uncertain auth
response retains the original use and cleanup responsibility without resend,
refresh or reconstruction from current configuration.

The pair adds two retained records, parent/grant/use/material references, a
digest string and scalar fields. Caller-owned form bytes, encoding/hash
workspace, signer/key backing, transport, response/token and callbacks may
overlap. Their original Ledger/holding must cover those lifetimes; a byte
ceiling or digest is not funding. The supplier drops references only through
its existing confirmed cleanup; this correspondence layer issues no release
or physical ACK. Canonical grant/use bodies and their initial identities are
unchanged. Physical auth transport, material admission and ordinary numerical
capacity are separate acceptance boundaries.

Runtime bundles support package, signature verification, installation,
activation, drain, rollback, and reclamation through standard operations. The
verified component is bound to the loaded component. Old code is retained
while execution, readers, or cleanup require it; historical verification keeps
the manifest, signature, and required decoder rather than every old executable.
OCI and existing signing tools are candidates, not semantic requirements.

The native signature adapter dynamically loads OpenSSL 3 and invokes its EVP
Ed25519 verifier. It does not implement a cryptographic primitive. Portable
MoonBit control selects the signature scheme, authority, exact canonical
preimage, and accepted key scope; the adapter reports only key decoding and
signature verification observations. The configured library path is an
explicit native deployment dependency rather than a hidden Node fallback.

The initial filesystem adapter accepts a pre-positioned component and a signed
canonical bundle envelope. `runtime-bundle-cli.mjs` exposes `install`,
`activate`, `drain`, `rollback`, `verify`, `inspect`, `active`, `list`,
`recover`, and `reclaim`. Its configuration names the Site-local Store,
target triple, and configured issuer public keys. The adapter copies through a
bounded buffer, verifies the component digest before adoption, and makes the
Site-local active revision durable in SQLite. These filesystem and SQLite
operations are environment-specific; canonical identity and every lifecycle
transition remain MoonBit decisions.

The native distribution exposes the same lifecycle through the
`actql-native-runtime-bundle` MoonBit executable. It loads explicitly selected
SQLite and OpenSSL libraries, reads authority and envelope inputs through
generation-pinned files, and streams a component in bounded chunks. Each
invocation reopens the durable catalog, so activation, rollback, drain,
reclamation, inspection, and recovery exercise the restart path rather than a
process-local cache. The executable contains no Node subprocess fallback.

The native filesystem adapter can adopt an exact pre-positioned generation or
create one through a bounded streaming installer. Installation first records a
capacity reservation and exact signed intent in the canonical SQLite catalog.
It then writes bounded chunks, verifies the streaming digest and exact
generation, and atomically replaces the staging responsibility with the
installed entry. A crash before that replacement leaves both names and the
reservation discoverable for exact-generation recovery; it cannot leave an
uncharged installed file. The Store holds an exclusive process lock while it
may own writers or perform recovery, so a second live process cannot reclaim
an active installation as crash residue.

The same catalog binds the active revision, portable lifecycle state, owners,
physical generation, and retryable reclaim responsibility. Reopening the Store
re-admits every signed manifest before any operation and upgrades the earlier
catalog envelope without changing its admitted bundle records. Shared
immutable components use one capacity reservation and are deleted only after
the final bundle and owner release them. The separated-network update profile
and packaging of the executable with a complete native Site distribution
remain later integration steps.

Remote dispatch resolves only a registration for the exact active bundle. It
compares the requested Connector registration, Connector revision and strategy
revision with the admitted signed manifest before invoking the component loader.
The runtime capability and evidence issuer then use that admitted member tuple.
Sharing physical component bytes across individual Connector manifests does not
grant another manifest's member or operation capability.

The runtime retains a durable bundle owner before execution, verifies the installed
artifact immediately before invoking the registered handler, and releases the
owner only after physical output cleanup and Site holding release. Activating
a new revision therefore drains the prior revision without invalidating an
already admitted attempt. Reclamation is retryable and cannot remove an
artifact still referenced by another bundle or owner.

### Scoped bundle retention before a Run

The opt-in Node HTTPS custody endpoint reuses the Site's mTLS Coordinator
authentication. Its explicitly configured allowlist binds Coordinator authority,
Workspace, authority scope, environment and one already registered runtime bundle.
The registered capability fixes the Site generation and exact signed member tuple.
Only querying that member's custody, retaining it, and releasing the caller's exact
owned hold are exposed. Execution grants are not bundle-administration grants.
Installation, activation, draining and reclamation remain separate existing
operations. A Site without this extension refuses the endpoint; clients never
substitute an older dispatch or treat an unsupported response as readiness.

An immutable distribution is a canonical bounded list of existing bundle CIDs.
It is membership metadata, not evidence of signature verification, installation,
or authority. Each selected Site re-admits its stored signed manifest and checks
the physical component before new retention. Its ordinary bundle capacity and
owner limits still apply; the manifest's physical-component limit is not a
Connector-count limit.

The caller persists a unique flat preparation nonce and the exact Set/member
scope. An initial nonmutating query returns a binding to the Store's catalog
incarnation and observed bundle revision. This response does not hold anything.
The caller must persist the returned canonical binding and CID before requesting
retention, and recover uncertainty by querying that same binding. It must not
refresh a nonce or revision to replace an unresolved request.

Owned holds use the existing bundle record and `bundle_holds` transaction, under
the reserved `set-retention:` identifier namespace. Legacy hold APIs refuse that
namespace. An exact retained retry does not increment ownership again. A new
retain requires the binding's original revision and ordinary active-bundle
admission. If release arrives first, the common owner increments only the existing
record revision; that fences the delayed retain without a tombstone or another
journal. A missing row is conclusively fenced only in the same catalog at a higher
revision. Equal revision remains unresolved; missing or inconsistent state is
unavailable. Other owners can cause a legitimate revision conflict, which does
not constitute a policy refusal.

Fresh catalogs initialize their own random incarnation. Legacy catalogs retain
their existing behavior and need explicit `initializeRetention(control)` opt-in
before this interface is available. Invalid or partially missing initialized
metadata fails closed. Replacing a catalog does not reuse old hold bindings.
Restoring a historical backup under its old incarnation is outside this monotonic
storage contract; recovery must establish a new incarnation rather than silently
rewinding accepted revisions. No automatic recovery or migration performs that
replacement. Release can dispose an exact owned hold even if its physical bytes
are unavailable; corrupt binding or signed record state retains responsibility.

The caller's existing accepted-preparation and Run records decide when a Set hold
may be released. A custody response does not prove those references have ended,
and this endpoint does not create a Set activation transaction or a second Run
lifecycle. In the initial topology, different Set revisions name separately bound
Sites; changing the Cloud active Set does not drain a Site still needed by old
work. Its later dispatches continue to use ordinary active-bundle admission and
current execution authority. The transport-specific custody adapters preserve these same common operations;
transport acknowledgement never replaces the original Store observation.

## Installed Row credential issuer loading

The ordinary Run Credential Site and the Salesforce compatibility installer
load their selected issuer through `loadRowSourceCredentialCustody`. The
existing Row Site owns private-key admission, optional CA acquisition, the
original Journal opener, grant signing and release. The installer retains its
own profile, Account context and Site-binding preimages, refusal codes and
provider-specific operation admission. No key or second credential issuer is
returned to a Connector driver.

Key and CA acquisition and Ed25519 admission precede construction of the
installer's default secret resolver and opening its Journal. The resolver
factory is synchronous, receives no private material and does not resolve a
provider secret. Failure before Journal acquisition cannot create a Journal
cleanup duty; after acquisition the same existing custody owns close, pending
release and retry. Loader completion is neither current permission nor a
physical release acknowledgement. The original profile/key/CA input bounds
and the simultaneous decoded-key and retained-custody inventory remain the
caller's resource obligation.

The installation-metadata alternative keeps its separately bounded key read,
original initialization-failure carrier and after-await current fence. It does
not acquire Run grants or defaults through the compatibility loader. Scope,
signature preimages and per-use Journal checks keep their existing Owners.

## Pre-Run Bundle custody on the outbound channel

The existing authenticated outbound channel distinguishes `RemoteSitePollOperation`
from Run-only `RemotePollOperation`. Its `Run` variant preserves every existing
operation. `BundleCustody` carries the common custody request and the original
positive JSON-safe `delivery_revision` from the pending Set/member compare-and-swap.
It has no DispatchRequest, Run, execution budget, or execution authority.

The canonical poll wrapper contains `delivery_revision`, `request_cid`,
`request_json`, and version `actql-remote-poll-bundle-custody/0.1`.
The canonical observation contains `delivery_revision`, `request_cid`,
`response_cid`, `response_json`, and version
`actql-remote-bundle-custody-observation/0.1`. Both have a 131072-byte total
UTF-8 bound. The common request/response wires, their CIDs, and their existing
65536-byte bounds are unchanged. Strict field and canonical-byte checks reject
shape changes, duplicate fields and identity substitutions.

The Coordinator's original Set/member row supplies routing and authority; a
caller-supplied request CID is only an index. It admits the response against its
persisted exact request and pending member revision before acknowledging the
persisted outcome. The canonical ACK contains `delivery_revision`, `request_cid`,
`response_cid`, and version `actql-remote-bundle-custody-observation-ack/0.1`.
HTTP 200, another response, or a late reply for another delivery is not an ACK.

The Native receiver requires explicit trusted workspace, authority-scope and
environment configuration alongside its existing Coordinator/Site/generation/
Bundle/Connector registration. Missing scope configuration refuses custody.
Immediately before Store access it checks the authenticated Coordinator, exact
current scope, and admission-open status for retain. It checks the actual stored
manifest's Connector registration and revisions, then invokes the original
Bundle Store custody operation. Query and release cannot manufacture retention.

The resident control process uses its existing exclusive executor slot for this
Store access. One bounded in-process slot retains a delivered request while a
holder owns the Store, then retains the exact Store response until its checked
ACK. No further poll is accepted while this slot is occupied. Existing control
pacing governs waiting and ACK retry; retry sends only the retained response and
never reopens the Store or repeats its operation. Unconfirmed Store or slot
cleanup produces no response success. Shutdown with pending custody is reported
as unknown.

This bounded process-local custody is not a durable context-response ledger.
A process restart without its original context response cannot claim that context
or construct replacement evidence. Retain and release reconciliation use the
original durable binding, catalog incarnation and Store fence. An exact canonical
`actql-remote-bundle-custody-observation-disposition/0.1` response may retire only
the transport duty: it names `delivery_revision`, `disposition: "obsolete"`,
`request_cid`, and `response_cid`. The current Set Owner must first validate the
original typed response and prove that a newer or retired authoritative member
duty supersedes it. HTTP 409 with that exact bound disposition releases only the
process-local response slot, allowing the next original current duty to be
polled. It neither acknowledges retention/release nor repeats a Store operation.
Generic 409, unknown or mismatched replies retain the response slot until a
checked ACK, checked obsolete disposition, or explicit shutdown. A disposition
never authorizes replacement context or a new Run.

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
## Original Salesforce Account conditional target observations

The Salesforce Target Observation owner has a distinct Account-by-record-ID
read profile for strong conditional evidence. It uses the original read grant,
one ordinary Credential use, the checked candidate's exact GET path and an
empty body, with explicit JSON Accept and identity Accept-Encoding. It does
not substitute a target read for a write decision or issue a mutation grant.

Only that actual acquisition registers a private original. Its synchronous
receiver requires the same candidate request, Catalog, runtime and Credential
control/Journal, and verifies the original grant and use occurrence through the
existing Credential receiver. Copied records, restored Catalogs and scalar
ETag or CID values cannot register an acquisition. The existing target version
continues to identify its original response and provider target; an HTTP ETag
is a separate fact and never replaces that version.

The conditional representation requires one strong ETag of at most 1024 HTTP
header characters and either no content encoding or a single identity encoding.
Quoted empty ETags are representable; weak tags, wildcard/list forms, missing
tags and duplicate ETag headers are unsuitable. The Credential owner retains
the actual raw-header multiplicities privately because Node's normalized
singleton headers can conceal duplicates. It remains the sole response-byte
membership and digest authority. These facts do not establish that a different
object, external-ID path, collection, upsert or DELETE supports exact atomic
conditions.

The receiver rechecks original membership and bytes after the finisher and its
result inspection, even when either throws. An observed integrity refusal is
terminal after byte restoration. The original finisher exception and confirmed
Journal outcome remain unchanged. Cancellation or retirement during the borrow
cannot publish its result; neither changes a confirmed acquisition into an
unentered use or permits a resend. Retirement drops only this receiver's
references. Escaped aliases, the enclosing prepared child, actual response
custody and physical cleanup retain their existing owners and accounting.

This receiver does not mint conditional request identity, durable saved
evidence, cold-restoration authority, write approval or physical cleanup ACK.
Those remain separate admissions by the existing request, Preview, Store,
Credential and Effect owners.

## Original sealed Checkpoint bindings

The Effect Run binding facade retains the admitted nominal sealed Checkpoint
with its exact original Allowed Run and Run Definition. Its visible metadata
fields keep their existing meaning. The pure facts accessor requires that
same returned binding and those same original handles; copies, another package
instance or changed roots cannot borrow it. It does not parse the wire again
after a helper or await. A restored operation admits its own original once.

The binding lives with the existing restoration operation. It is not a
wire/CID cache, persistence receipt, permission or approval. Actual custody
and its `PersistedCheckpoint`, the saved waiting projection, current gates,
control revision and conditional commit remain with their existing owners.
Dropping the binding's managed references is not physical cleanup or an ACK.

A pending cancellation request does not prove a waiting exit. The same sealed
Checkpoint and waiting projection remain until the actual Run owner confirms
the required stopping and outcome facts. Its advisory `resolve_checkpoint`
action grants no review or resume authority; the current cancellation gate
continues to refuse approval, resume and dispatch, including after restore.

The same nominal association may supply the original to the existing persistence
confirmation and waiting-state writer in the same Common module. The caller
supplies the exact stored wire from its actual selected read; the original
custody, revision and current/cancellation gate remain separate. This avoids
wire readmission or moving an opaque object between independently loaded bridge
modules. Full emitted waiting-state bounds and the existing advisory
`resolve_checkpoint` identity remain unchanged.

The transient native Array snapshot overlaps the writer's sorted Result names,
availability fields and emitted wire under its existing full-wire limits. These
managed values follow the restoration operation's existing accounting and
lifetime; they do not acknowledge physical release or cache a current grant.

## Pre-Checkpoint Effect Run observation

The existing Common Effect Run owner projects an unpublished candidate from
its original allowed Run, definition, authority and admitted Coordinator task
records. The Host supplies the complete saved claim set and checks each task
and dispatch against that same Run. The projection neither prepares a Pure
Run nor derives a public Run revision from a Coordinator revision. The existing
Run observation owner issues the final revision through the same durable row,
observation key and conditional commit, with current authorization checked
independently before disclosure. Observation time alone does not advance it.

Computation completion is not Effect completion or publication readiness.
Task settlement and task cleanup cannot complete whole-Run cancellation:
producer, retained-input Transfer and Effect stop/custody proofs remain with
their original owners. Without those proofs the candidate stays nonterminal
or requires reconciliation. A cancellation request is not a pre-start fence,
a confirmed Checkpoint or approval. Missing claimed observations are not
converted into a known execution outcome or permission to resend.

The thin package bridge captures each native Array entry once without using
caller-owned iteration, validation or copying methods. Original Run handles,
durable wires, claim snapshots and parallel ABI arrays overlap with the Common
projection, encoded candidate, task/scopes/work arrays and frozen JavaScript
result during the read. These representations retain the existing Host
accounting and lifetime obligations; projection or garbage collection is not
physical retirement or a resource acknowledgement. The returned task cleanup
facts are explicitly separate from whole Effect/Run cleanup.


The original Checkpoint reconciliation projection uses the same nominal
binding and Allowed/Definition roots as waiting projection. It confirms the
actual stored Checkpoint wire, derives authoring context from the original
prepared source, binds the complete Preview and actual Invocation to that Run,
and delegates complete set/member receipt admission to the existing Run-state
writer. Only admitted unknown members appear in `needs_reconciliation`.
This projection does not issue an outcome, approval, grant, physical-stop or
cleanup receipt. The authenticated Journal/report owner retains actual receipt
custody, revision/current/CAS checks and same-dispatch reconciliation; no resend
is implied. Restored or foreign runtime namespaces admit their own originals.


Confirmed cancelled/unpublished projection may reuse the same original review
binding and actual stored Checkpoint wire. Its Run ID comes from the original
Allowed/Definition association; it accepts no caller cancellation or stop Bool.
The existing pure Run-state writer emits DATA only. The actual Host retains
all whole-Run no-grant, no dispatch/unknown outcome/publication, physical stop,
revision/current and CAS duties. Pending requests or task cleanup alone cannot
select this terminal projection, and the reconciliation path remains separate.

## Effectful publication forwarding

The Run Host facade forwards the existing complete Effectful receipt and
publication checks to the Run Publication owner. Preview admission binds its
wire to the independently supplied original Run identity and authoring context.
The facade retains that actual Common value in its module namespace; a copied
handle, scalar identity or foreign namespace cannot replace it. Its immutable
member count bounds receipt capture before reading the member array.
The pure semantic-identity observer supplies the existing Preview CID for the
original Checkpoint join; it is distinct from a full Store byte digest.
For an already admitted original Checkpoint, the Run Host's Preview reader
uses the same Allowed/Definition association and actual stored wire. The
existing Common owner derives authoring context from its original checked
Effect source and matches the Preview to that Checkpoint. The caller supplies
no replacement authoring identity or Effect-free preparation. Reconciliation
uses this same admission before inspecting its actual invocation and receipts.

Final receipt issuance requires the original Run Definition, computation
Receipt, captured Run, Preview and complete set/member receipts. Commit
validation additionally requires the Invocation, all Result Definitions,
artifacts, derivations, orderings, retentions, durable bindings, manifest and
the original publication request/attempt/index chain. Visible contract fields
cannot replace the retained Common contract. Missing or refused evidence does
not produce a successful receipt or commit.

These synchronous functions inspect historical DATA. They do not acquire
resources, grant current approval, dispatch an Effect, settle cancellation or
Unknown, perform a Store CAS, or acknowledge physical mutation or cleanup.
The actual Host retains those existing operation and lifetime duties. Typed
forwarding alone does not establish a matching compiled package or an executed
public operation.

## Effect completion report and persistence response

The existing protocol Owner carries the complete opaque final carrier in
`actql-remote-effect-completion-report/0.1`. It binds the exact carrier bytes
and their CID to the receiver's original approved resume delivery: Dispatch,
Checkpoint and review report, Resolution and verified Resolution, resume intent,
claimant and generation. The report CID covers the canonical outer object.
The inner String is unchanged, including whitespace and escapes. Borrowed
original completion inputs alone are not a complete final carrier.

This is transport admission, separate from the receiving Owner's complete
Common Completion admission and current Site/Run/resume checks. Historical
delivery DATA cannot renew execution authority. The caller funds the actual
carrier, UTF-8/hash workspace and encoded/decoded outer overlap under its same
selected bounds; framing that does not fit refuses without raising those bounds.

`actql-remote-effect-completion-reply/0.1` binds the same report, complete carrier,
Dispatch, Checkpoint, resume intent and claimant/generation. Accepted means the
existing receiving Owner has durably confirmed that exact completion through
its immutable save and Run CAS/readback. A codec cannot establish persistence.
Unknown save produces no ACK: reconciliation retains this same report without
repeating the Effect. The response is neither a Checkpoint ACK nor a generic
completion proof, publication commit, permission renewal or cleanup ACK.

## Original holder terminal reports

The portable protocol represents an immutable ordered inventory of original
Dispatch requests. Construction and admission preserve DATA; they grant no
current permission, physical-stop authority, capacity release, or Run outcome.
The actual holder and receiving Run Owners retain those separate duties.

`actql-native-holder-terminal/0.1` is the closed canonical object with
`dispatch_request_jsons`, `root_request_cid`, and `version`. Each array member
is the complete canonical original Dispatch JSON, from the same Run,
Coordinator and Site execution scope. The root must occur exactly once;
duplicate task keys or request identities refuse. Bounds remain the receiving
operation's configured byte limit. Returned request arrays are copies.

A receiving authenticated Owner must retain the exact original association
before returning the closed canonical `actql-native-holder-terminal-ack/0.1`
object: `report_cid`, `root_request_cid`, and `version`. The typed report and
correlated reply must belong to the same original module namespace. This
receipt acknowledges only that inventory; a partial inventory does not
confirm the entire Run, authorize another dispatch, or retire its wake.

The Coordinator facade keeps the original Common value behind an opaque
handle. Copied objects and caller-authored projections cannot substitute for
its admitted request inventory. Restored durable bytes require normal typed
admission; cross-process pointer identity is not a restoration requirement.
`physical_stop` becomes confirmed only through the existing Run Owner's actual
same-Run holder coverage, current authorization and durable revision/CAS
connection, independently of report serialization or process exit.

## Completed cold cleanup custody

The existing `RemoteRuntimeCustody` separates readable completed restoration
from cleanup-only completed restoration. The readable constructor retains its
Active-only contract. A cold cleanup constructor accepts the same typed durable
completion in Active, Releasing or Unknown cleanup, checks its original request,
evidence, output subject and measurement together, and retains the checked
material/holding/evidence binding and observed revision. Current Site authority,
original Source, physical generation and exclusive handles remain independently
checked by their existing environment Owners before construction and release.

The cleanup-only marker cannot be confirmed into readable restoration. Success,
new execution and failure reclassification remain refused even after all
resources return. The same existing cleanup planner checks the current record
and monotonic revision against that original binding. No absent process-local
handle can erase historical output, holding or bundle debt: every original
resource disposition must be reconstructed before planning release, and all
three require their existing Owners' actual release observations. No synthetic
holding, new output, fresh execution custody or replacement publisher is issued.

A settled operation is distinct from released resources. Pending stop, uncertain
Resource release or uncertain durable COMMIT preserves its original duty; neither
process exit nor NativeSettled alone acknowledges physical cleanup. The durable
release transition is selected only after the same original custody observes all
resources reclaimed, and the permanent cleanup-only purpose still forbids output
or execution admission afterwards.

The private purpose variant replaces the old completed Option-plus-tuple envelope
within the same custody. It introduces no additional owner, registry, handle,
owned text or larger logical constructor representation. The installed caller
still retains that custody in its actual funded control slot before fallible
continuation. Core's bound checks and logical representation do not supply a
physical handle, capacity grant, Account permission or a successful cleanup ACK.
