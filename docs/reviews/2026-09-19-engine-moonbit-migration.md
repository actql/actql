# Engine MoonBit ownership migration

Date: 2026-09-19. Branch: `feat/engine-remote-site-completion`.

This ledger records product decision owners while the Engine milestone moves
common control out of handwritten environment code. It is not a completion
report. A row is complete only when every product caller uses the MoonBit
owner and the superseded decision implementation has been removed. The
current Engine milestone reached that condition on 2026-09-21; environment
adapters listed below retain physical I/O and observation state only.

The authoritative closure summary is the
[Engine and Remote Site completion result](2026-09-21-engine-remote-site-completion-result.md).
The detailed rows below retain the incremental migration rationale; earlier
sentences that describe a later-closed item as open are historical, not the
current acceptance state.

| Boundary | Product owner | Adapter responsibility | Current removal condition |
| --- | --- | --- | --- |
| Publication contract identity and admission | `run_publication` | Persist and retrieve admitted wire | Complete for current publication callers; the independent JavaScript fixture remains test-only. |
| Publication and delivery progression | `run_publication` | Perform bounded Store, clock, and sink operations | Product Result access follows the portable authorization, resolution, availability, admission, grant, and delivery order. Native publication validates the complete Run-bound chain, persists canonical Result schemas, installs one scoped durable index, and requires that commit before formal delivery. The standard native publication service issues request, attempt, and public-index contracts from an admitted intent, checks Host authority before Store lookup and again against the candidate index, reconciles exact retries before creating an occurrence, and revalidates a concurrent or restart-visible winner. Restart retrieval re-admits stored contracts and schemas, then portable control selects the exact indexed Result binding. The standard native Result-access service performs Host authorization, egress admission, grant issuance, current-authority rechecks, and formal delivery without Node. Native delivery persists formal attempts, sink-confirmed progress, receipts, terminal records, and restart reconciliation through MoonBit actions. |
| Durable publication payload lifecycle | `publication_payload` | Stream bounded bytes, persist exact transitions, and reclaim exact generations | Native filesystem and SQLite adapters use the portable owner. Exact generations are checked against durable Result bindings before commit and delivery, committed indexes survive restart, and trusted clock observations retain their monotonic lower bound through SQLite CAS. The standard native publication service composes these physical operations without exposing request, attempt, or index construction to an environment adapter. |
| Durable Result row framing | `run_publication` | Supply bounded byte chunks and await emitted rows | Product Local and DuckDB imports, retained examples, and formal publication delivery use the MoonBit owner. The handwritten JavaScript parser remains only as an independent physical fixture. |
| Execution Site and Transfer lifecycle | `execution_site`, `physical_strategy`, and `remote_transfer` | Stream bytes, observe stop, persist exact transitions, and retain physical handles | Remote paths use MoonBit transitions. Remote execution custody now records operation settlement, output ownership, Site holding, bundle holding, stop confirmation, and independent release in one portable owner. The Node runtime performs the physical close and release operations but no longer derives aggregate reclamation from its own flags. In-process managed Transfer also has one MoonBit progress owner for source stop, Site settlement, destination admission, holding, reclamation, and cleanup release. Standard Host task success now records Site readiness, common completion, output retention, Site settlement, and managed binding validity in one MoonBit progress owner. Standard Host cleanup similarly owns its retry and close-wait sequence in MoonBit while taking current physical responsibility as adapter observations. Failed Site operations keep stop confirmation and settlement in another portable progress owner. Retained-output owners share one portable close state and keep each holding release in its own portable state, so one physical close may safely govern outputs from multiple Site operations. JavaScript performs selected physical actions and reports observations instead of supplying independent Boolean lifecycle snapshots. Remote Transfer has one canonical durable record that re-admits its request, ordered physical manifest, and independent state planes. Admission envelopes and direct and Store reply bodies have one MoonBit emitter and admission path shared by Node and native HTTPS adapters. The native direct client verifies each admitted chunk length and digest before sending one bounded chunk at a time. The native Store route durably seals an upload, resumes without rereading the source, reserves destination capacity, verifies bounded downloads into independent file generations, and persists the exact destination receipt before completion. Reopen verifies the retained generations and receipt without retransferring payload bytes. Native SQLite rejects different content for one occurrence and restores both Transfer and Store-reader state only through the MoonBit owner. Store and direct failures now retain durable ownership until the exact remote stop and temporary-generation cleanup are confirmed. A lost direct commit response remains in reconciliation and cannot delete a possibly committed destination. A live direct receiver can reconcile that exact commit without rereading source bytes. A fresh receiver returns cleanup-confirmed history, but it keeps historical commit and unfinished records reconciliation-required until current destination material is recovered independently. The remaining in-process orchestration stays open. |
| Remote dispatch and reconciliation | `remote_site_protocol`, `platform_native/remote_runtime`, and `platform_native/remote_agent` | HTTPS, SQLite, bundle, and registered physical executor operations | Current Node and native integration slices use the portable owner. Runtime success, failure, and cleanup plans consume the portable custody record rather than adapter-local lifecycle decisions. The common success planner orders bundle retention, Site operation admission, physical execution, output holding, settlement, durable output evidence, and terminal ownership; the Node runtime only performs the selected physical action. The native runtime now executes that same plan directly, durably accepts the dispatch before invoking a registered executor, retains output and bundle custody, and preserves stop-unknown failures until cleanup is confirmed. Every registered executor receives the admitted dispatch budget, and every successful output must expose a bounded physical reader. A native executor registration can now be created only from the opaque binding issued after the durable Store verifies the exact active component and target and acquires its process-level holding; raw bundle and Connector strings no longer grant runtime registration. The runtime owns that holding after successful registration, rejects new work when the active binding drains, and releases the holding only after all dispatch and output owners close. After acquiring the exact output holding, portable control derives its evidence identity from the dispatch, Site generation, material generation, and retained-byte charge; neither a Node nor native executor can supply an arbitrary holding authority CID. The common runtime binds each reader to the exact dispatch and material generation, rejects oversized chunks, and keeps output and Site holding ownership until physical finish or close is confirmed. A product registry bridge now executes exact configured standard Local and DuckDB tasks, derives all output identity, measurement, manifest, and retention facts from their common completion, and exposes only a bounded replay reader to the runtime. Its standard SDK composition accepts only opaque task executors produced by that bridge, then binds the complete registry to one verified active component before opening the runtime. A standard task can now open only through a resolver that receives the exact dispatch and input binding, returns an opaque bound Run, and retains its input owner until the synchronous Connector has stopped reading it. The earlier fixed-CID plus zero-argument Run factory has been removed. Both real engines enter that registry through the native outbound Agent's durable acceptance, execution, terminal observation, and release progression rather than a direct runtime shortcut. An unconfirmed acceptance starts no native work, exact retransmission retries observation without duplicating execution, an unknown terminal delivery returns the exact completion for reconciliation, and an exact release retry observes the same durable cleanup rather than releasing twice. Real SQLite, filesystem, signed-bundle, Local, and DuckDB tests cover these boundaries. A common registered physical-source resolver now owns row-wire admission, ordering, completion, capture, and input release for every accepted representation. Its incremental prepare, bounded-frame feed, finish, and cancellation boundary lets asynchronous adapters supply physical bytes without acquiring a second framing or completion state machine. A dispatch-bound incremental session also fixes the exact input binding and defers Run construction until final input verification succeeds. It rejects oversized frames, truncated chunks, reordered chunks, and foreign physical bindings before capture. The durable Store route supplies only verified physical streaming and lifetime observations, and a bounded direct-provider fixture passes through the same resolver without a second semantic implementation. The live Node direct receiver now exposes its exact admitted input binding and bounded frames through a thin session adapter. The corresponding MoonBit API admits and rechecks the exact Transfer request and destination receipt before and after streaming; JavaScript does not interpret rows or decide cleanup eligibility. The Store resolver still re-admits its canonical Transfer binding, pins the exact committed destination generation, verifies physical digests while streaming bounded row wire, and establishes completion and capture only through the registered MoonBit evidence boundary. A real Store-route test now uses the product outbound gateway and portable canonical admission in the Coordinator process. A separate native process polls it over mutual-authenticated HTTPS, posts durable acceptance, executes the registered standard resolver and Local task, posts terminal status, exposes bounded output, and posts exact release status. It also rejects foreign receipt identity before opening a Run. The gateway keeps an accepted dispatch until terminal status instead of losing the second observation. The live Node adapter now accepts only the generated MoonBit source control and an opaque source factory from the verified active component; the arbitrary JavaScript session-control loader has been removed. The native Store route similarly installs one opaque factory that fixes the Store, codec, checked Program identity, bounds, and Run constructor before runtime admission. Installing this registry in the complete native Site Agent executable and completing the separated-network profile remain open. |
| Runtime bundle lifecycle | `remote_bundle` | Verify signatures, install bytes, synchronize files, and persist transitions | Product dispatch is bound to the active bundle. Signature scheme, canonical preimage, envelope admission, issuer and key selection now have one MoonBit owner used by Node and native callers. The complete drain-and-activate plan is also one portable transaction decision; Node only persists the projected transitions and active binding. The native OpenSSL adapter reports Ed25519 verification without owning those decisions. Native streaming installation reserves capacity in the canonical catalog before creating output, bounds each append, and records intent, acquired file ownership, and the sealed generation as separate durable phases. Recovery deletes only the recorded allocation and retains reservation through directory-sync retry; an unproven create-to-record crash window remains quarantined. An OS lock prevents a second live process from mistaking an active writer for crash residue. Activation, drain, rollback, owners, restart, and final-reference reclamation remain in the same Store. A MoonBit executable now exposes the standard update lifecycle without a Node runtime and reopens the durable Store for every operation. Its versioned multi-key trust input separates historical verification from new-install authority, so rotation does not either revive an old key or erase acceptance history. The first native loading profile uses a complete statically linked Site executable because the MoonBit native backend does not currently emit linkable foreign-library artifacts; [the loading decision](../design/native-runtime-bundle-loading.md) fixes the process and generation boundary. Packaging that executable with the complete native Site and exercising update across the separated-network profile remain open. |
| Credential use | `remote_credential` | Resolve and apply a secret within a scoped HTTP operation | Node integration is connected. Native SQLite claims and the bounded HTTPS operation now enforce the portable grant without exposing the secret; binding that service into the complete native remote-dispatch Host remains open. |
| Local and DuckDB task progression | common Host and Connector packages | Native evaluation, database calls, cancellation delivery, and stop observation | Handwritten Node orchestration still contains migration targets. Local, reference, and DuckDB Node failures now use portable progress owners from physical cancellation through independent retry, settlement, cleanup refresh, and terminal release; the Node adapters retain only physical operations and observations. The native DuckDB adapter exposes bounded streaming metadata and physical column batches, binds admitted parameters, and executes standard acquisition metadata, validation, and result statements in one real transaction without a Node process. Native fixed Compute now consumes an exact portable driver configuration, bounds input batches before transaction start, streams real DuckDB results through the portable receiver, and requires exact physical settlement before common completion. The DuckDB driver no longer selects between legacy and common completion or manufactures Connector-owned finish and publish callbacks: every product and conformance caller enters the common materializing boundary with its exact admitted output. The obsolete Connector-owned `finish` and `publish` callbacks, `TaskPublication`, legacy start and completion entry points, and their compatibility fixtures have now been removed from the SDK and common lifecycle. Local, reference, DuckDB, remote-completion fixtures, and `compute_author` all use the same materializing or managed completion authority. The standard dispatcher path registers the common task before native I/O and closes native execution before common settlement and DAG completion. The standard Local dispatcher and exact checked Named Result export now run on JS, Wasm, and native through one portable publication owner; generated Node and Workers bridges delegate to that owner. Native Local and DuckDB integration both establish the real publication attempt before payload creation, stream bounded replays of immutable Results into the durable Store, assemble the complete Run-bound evidence chain, commit every declared Result atomically, and resolve both Results after Store restart without Node. A product `NativeStandardStrategyRun` now owns the configured task loop, connects the exact portable Local or DuckDB selection to its physical executor, retains every common DuckDB runtime through downstream publication, and releases all owners without skipping independent cleanup. Its standard application entry executes the selected Local or DuckDB tasks, enumerates every checked Named Result, persists the complete Result inventory, and commits the formal publication without a handwritten environment state machine. The remote standard bridge derives exact physical evidence during the same bounded semantic export and replays the immutable output without allowing either Connector to manufacture evidence. A failed commit returns the exact prepared owner for retry or cancellation instead of re-executing the Program. Other handwritten Node orchestration still contains migration targets. |

The direct-input bundle boundary now uses one opaque MoonBit factory that fixes
the codec, checked sequence, Program identity, limits, and Run constructor.
Registration performs no physical access, and the exact Transfer request is
resolved before the Node adapter acquires a retained receiver claim. The
factory now opens one opaque MoonBit session that owns preparation failure,
frame rejection, cancellation, and the exact cleanup owner. The environment
adapter can only authorize, feed, finish, cancel, and retry that session; it no
longer constructs a parallel input-failure lifecycle. Cleanup completion is
also monotonic state on the MoonBit failure owner, so repeated adapter retries
cannot release the physical input twice. A Run-independent source factory now
ends at the same verified captured-source boundary, allowing an asynchronous
Host to execute after verification without duplicating the native Run type or
the input state machine. The generated Node product bridge now exposes that
opaque factory, session, captured source, release owner, and cleanup owner.
The Node adapter awaits the selected environment execution as a physical
operation and returns failed release to the same MoonBit cleanup owner.
The bounded physical-strategy application builder now links and runs its
independent tests on JavaScript, Wasm, and native. Its JavaScript export names
are target-specific wrappers over the portable product functions rather than
the only callable implementation. This makes the existing Program checking,
graph construction, and Local or DuckDB selection reusable by a native Site
application without adding a second parser or planning implementation. A
native application profile now opens that portable strategy dispatch from an
exact captured input and transfers both the standard Run and Captured DAG
cleanup owner into the remote runtime boundary.
The profile now loads a bounded immutable application definition through the
native filesystem adapter, registers Store and direct factories from the
portable checked input identity, and composes the exact Store task into the
process-owned Site distribution. A Node-free product executable now loads that
checked application, verifies the active signed runtime component, fixes the
Site generation and capabilities, opens both durable journals, binds the real
native DuckDB driver and Store input, and polls only through that process-owned
distribution. Its physical configuration surface does not install another
progression callback. A real separated-process dispatch through this
executable now includes output Transfer and publication operations before
release. The runtime projects immutable output facts from
the exact durable dispatch observation without opening a physical reader.
The application owner uses those facts to derive both the publication payload
request and the direct or Store Transfer request from one canonical
Coordinator intent. The authenticated polling protocol carries that intent as
an operation distinct from dispatch, query, and release. The application Site
reconciles the retained completion, reuses an exact sealed publication payload
on retry, and drives the selected durable Transfer route without rerunning
Compute.
The observed generation, physical manifest, logical view, schema, codec, and
source Site generation cannot be replaced by the executable adapter. The Site
now posts one canonical output result, and the Coordinator gateway re-admits
its exact payload and Transfer bindings before resolving the operation. The
Coordinator now durably installs that exact output intent before transport,
records an uncertain response without authorizing source release, and commits
the re-admitted result through a MoonBit-owned transition. SQLite restores the
canonical payload and Transfer requests after restart; an unknown operation
may retry only that occurrence, while an already committed result returns
without repeating transport or Compute. The separated-process product E2E
uses that path before release. The live Node
bundle boundary and the native durable-Store route now install opaque
factories directly; neither
accepts a replacement input state machine from application composition. The
native standard registry also accepts non-streaming Local and DuckDB Runs only
through an opaque factory fixed to one exact input binding. Its earlier public
request-resolver and raw Run-binding APIs have been removed. One MoonBit Site
component now fixes that registry, active runtime, durable journal, outbound
client, and control endpoints before polling; application code no longer joins
an arbitrary runtime to the Agent progression. The standalone journal and
transport CLI is control-only and rejects dispatch work because it has no
verified runtime registry. Only the runtime-linked Site component may durably
accept a dispatch. The process-owned distribution additionally closes the
common runtime before the active bundle Store, dispatch journal, and HTTPS
client. A failed earlier authority remains retryable and prevents later
physical owners from being closed out of order.
Successful dispatch observation now returns the exact admitted request and
portable runtime completion, not only a detached CID. Downstream publication
or Transfer composition can therefore consume the established occurrence
without reconstructing dispatch identity in an environment adapter.
The process-owned Site distribution resolves that observation through its
durable journal and opens only the exact retained material generation whose
subject CID matches the portable completion.
The application Site owner closes that distribution before its transferred-
input journal and retains either failed step for retry; executable code does
not infer that a returned poll or close call released physical authority.
Each exact standard Run now owns its captured output cleanup separately from
its input pin. Runtime stop, captured-output release, and input release advance
monotonically and remain independently retryable, so a complete Site process
does not depend on a conformance fixture to release the Captured DAG after an
output reader closes.
Store and direct input factories must return this opaque compute owner rather
than a raw strategy Run, so attaching a physical input scope cannot discard
the independently retryable output cleanup owner.

The JavaScript retained-row parser is not a product authority after this
change. Its tests stay as independent physical fixtures; they are not used to
validate a second publication state machine.
