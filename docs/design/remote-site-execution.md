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
retains a durable bundle owner before execution, verifies the installed
artifact immediately before invoking the registered handler, and releases the
owner only after physical output cleanup and Site holding release. Activating
a new revision therefore drains the prior revision without invalidating an
already admitted attempt. Reclamation is retryable and cannot remove an
artifact still referenced by another bundle or owner.

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
