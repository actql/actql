# Retained result execution boundary

## Ownership and scope

A completed logical result and its currently usable physical representations
are different objects. Completion binds the exact producer, bound inputs,
operation obligations, output target, schema, ordering and required identities.
Representation admission binds that result to an immutable retained body and
the authority to use it. Equal CIDs do not establish ownership or availability.

The retained material distinguishes canonical logical row bytes from physical
holding bytes. The admitted content receipt and completion descriptor keep the
canonical quantity used by identity and logical encoding limits. Installed
Store wiring binds the actual physical quantity to the exact immutable copy;
the DuckDB Compute driver checks it against the admitted storage ceiling and settles
that quantity plus metadata. A smaller physical encoding does not reduce logical
budgets, and an expanded encoding cannot exceed its reserved holding silently.
The canonical-stream constructor uses the receipt's bytes for both quantities.
An alternative representation requires verified conversion and independent
storage sealing; supplying a byte count is not proof of either. Physical file
identity stays with the Store and never replaces the logical content CID.

The local Store accepts bounded UTF-8 text or bounded byte frames. Byte frames
are copied before awaited I/O so a producer can reuse its native buffer without
changing the admitted write. Frame and remaining-reservation limits are checked
before allocation and writing. Local and delegated writers use the same physical
hash and exact-file sealing boundary. `seal(identity)` additionally checks an
expected physical identity; `sealPhysical()` obtains that identity from the
writer's own accumulated bytes. Neither operation establishes a logical content
mapping or execution completion. Delegated writes send only the bounded terminal
physical report to the control Host, not their payload. Failed or interrupted
writes retain their existing cleanup and conservative accounting obligations.

Full-output representation transfer uses an exact `ProducerStorage`, not a
fabricated consumer `ProducerRead`. `RetainedStorageScan` decodes bounded rows
using the common typed decoder and canonical stream encoder without retaining
a complete value table. Its terminal proof matches the exact storage and ordered
content; malformed, changed, truncated or unavailable content cannot complete
the scan. The DuckDB resident importer converts these provisional values with
the same scalar conversion used by other imports. Neither a verified scan nor
successful parameter conversion proves native import, grants a consumer start,
or discharges that consumer's guard/demand budgets. Native transaction, copy
installation and resource settlement remain separate required boundaries.

An installed DuckDB contribution may combine independent retained-file output
with a resident DB copy. File work and its holding ceiling are configured before
offer construction; the selected offer separately covers the DB copy. The Node
bridge passes both requirements to the same common task admission. It secures
the file inside the resident transaction before committing the provisional
table, and publishes only after native settlement and common completion. The
resident environment can close without invalidating the independently held file.
Later resident consumers avoid reimport but still perform their required bounded
input checks. Eligible retained inputs are scanned directly from the owned DB
table in physical insertion order, through bounded physical column frames and
the same typed content verifier. The scan covers the full producer schema before
receiver projection. A logical column shadowing `rowid` excludes this direct
scan, leaving the checked file-read path; it cannot substitute a user column for
the physical ordinal. Query traffic is charged by the resident session, and file
traffic by the file reader when used. Copy reuse does not waive logical obligations.
The row-decoding fallback charges its retained-file bytes in fresh execution too:
native parameter accounting covers the later import, not the preceding file
read. Diagnostics distinguish these retained-input bytes from direct-file reads
and include them in total transfer, without charging an unused copy's file read.
Their validation-only input stream does not construct or serialize SQL parameters
for cells already held by the resident table. It still checks the receiving
physical types and finishes the same consumer measurement, demand and join checks.
For an exact claimed resident read, the installed driver may reuse the previously
admitted ordered identity. Its typed evidence binds the exact receiving input,
retained material and committed table generation through the active lease.
Unstarted, returned, retiring, foreign or unavailable leases cannot authorize
reuse. Availability is checked while reading and at stream completion.

This path omits canonical re-encoding/hashing only: per-value admission and its
cumulative limits still run. The trusted private DB reader supplies checked
values; arbitrary wire-row appends cannot use this evidence. Row-count mismatch,
value admission failure and consumer-budget failure still reject the input.
If the stored canonical byte/node/depth quantities exceed this receiving stream's
limits, it uses the ordinary verification path, preserving failure precedence.
The driver attestation relies on the managed connection preventing mutation of
committed table generations; a table name or equal CID cannot create it. No
cross-Run, restart or external-file reuse is implied.
A resident consumer verifies the selected DB copy rather than reading every
independent representation. File corruption is rejected when the file is
verified; a known revoked input material cannot be bypassed by a previously
imported resident table. Failed actual file reads retain their own stop/cleanup
responsibility, independently of native database settlement.
Other producer and storage verification scans use the canonical encoder's hash-only
sink: they do not reconstruct canonical output strings that no consumer stores.
The ordered CID and cumulative byte/node/depth limits are unchanged. Output
creation still uses bounded buffered encoding, because those bytes must reach
independent storage before publication.

Native stop and retained-input read stop are separate facts. If Store consumption
rejects without a read-stop receipt, the Compute Host cannot use DB settlement to
release that outstanding responsibility. It disposes bounded parser buffers,
preserves pending cleanup and does not retry the read. A supervising process Host
may establish final stop from actual execution-process exit, not a cancellation
request or a native connection's close acknowledgement.

`RetainedCompletionEvidence` projects a genuine completed retained output into
immutable, bounded metadata. It retains the exact completion identity, checked
sequence, target, input-binding identities and admitted content receipt, but no
output store, row buffers or physical/logical liveness callback. Evidence can
remain inspectable after a copy or local result port is revoked; this is not
reader authority. `retained_completion_can_handoff` separately requires the
same completion, exact admitted retained content and current use checks.
The transportable descriptor contains contract/content identities and bounded
measurements only. It cannot construct or re-admit a `CompletedOutput`.

An installed completion observer on the standard Node Host receives the common
core's actual output only after atomic completion and holding attachment.
Connector diagnostics and a resolved execution callback cannot trigger that
notification without common completion. Failed delivery stops future work and
preserves the completed task; delivery cleanup requires an explicit recovery
handle, otherwise its owner remains unconfirmed. Cancellation during delivery
does not authorize the next task. This supervision is not a replacement verifier
and does not itself establish control-side custody or cross-process admission.

The local managed assembly can install a process completion observer. It obtains
the genuine common evidence and exact material handle, then resolves that handle
to the same sealed process-Store lease. A copied body, equal CID or output label
cannot substitute for that lease. The observer is installed application wiring,
not an IPC option. Delivery is bounded by completion/input/column limits and the
channel's cumulative request and message limits; it contains no output rows.

Control-side completion custody accepts those notifications only from its exact
installed session and active request. It binds each one-time task occurrence to
an already sealed, live, identity-matching independent Store body. Storage sealing
alone does not create a completion record. Duplicate tasks, reused physical
bodies, foreign sessions, unbounded metadata and mismatched content are rejected.
The trust for successful computation comes from the installed standard Host and
common completion observer, not the storage digest or a general-purpose success
Boolean. This is a trusted local IPC boundary, not remote attestation.

Before binding a process or Store, custody snapshots the expected checked task
inventory. `CheckedTaskReference` projects existing Program/Unit definitions,
contract-set and bound Parameter CIDs together with exact input ports, producer
targets and control predecessors. It does not create a new identity domain or
replace occurrence-owned execution obligations. Its opaque local reference also
checks the bound producer owner and output target; equal metadata from a different
checked owner is not accepted as that owner's output.

The installed execution observer supplies this projection only after matching
the actual common-completed output. Custody compares it with the independently
prepared expected inventory, not a first-result guess. Later task records require
their non-acquisition data/control predecessors to have been recorded, and their
producer targets must match. Metadata arrays are snapshotted and bounded; changing
configuration after preparation cannot change the expected bindings. Acquisition
still has its own observation/capture contract. Task metadata and a surviving
file do not manufacture acquisition evidence or a receiving execution permit.

Custody records survive writer-process exit and consume their metadata quota
until the custody owner is discarded. Closing custody revokes retention use but
does not erase completed facts or unconfirmed Store deletion. This record layer
does not itself admit a producer in another runtime: checked-owner/input mapping,
the receiving authorization and resource admission must also be established.
In particular, the transport descriptor is not a serialized MoonBit owner, and
an internal task record is not permission to continue a failed Program.

`prepareReader` requires the custody owner's exact opaque completion handle. It
creates a one-shot physical-read service for a separately admitted execution
channel in the same Run and a different session. Before lending the body, the
service checks the reader's independently prepared task identity and current
custody/body availability. The returned metadata and bounded file lease carry no
row payload. This capability neither reserves execution resources nor admits a
logical producer: the installed reader assembly must perform those operations
through the common ledger and completion contracts before consumer execution.

`TrustedRetainedReadmission` is the low-level installed Host contract for that
logical step, separate from completion of a new Acquisition or Compute. The
proof-typed verifier must match exact surviving custody, checked task/input/
attempt provenance, receiving authorization, full-body verification and live
holding. The common boundary independently checks owner, target, schema,
registered contracts and complete content metrics. A descriptor or admitted
content receipt alone cannot readmit a result. An admission attempt is one-shot,
including rejection; it cannot restore old dispatch permission.

Readmitted outputs retain the receiving grant's logical revocation across
representation conversion, without consulting original upstream availability.
They can bind a new consumer but cannot satisfy the fixed-input completion check
of a currently dispatched task, even for zero inputs. Original process-local
ProducerRead identities are not fabricated. Each accepted local instance has
an opaque identity; identity continuity across processes is the exact installed
custody binding, not equality between process-local pointers or content CIDs.
The verifier is trusted installation, synchronous and side-effect-free; it is
not an option that Programs or arbitrary Connector results may supply.

The physical terminal report must belong to that exact borrow and active request.
Cancellation, custody close, malformed reports and rejected process-settlement
promises do not confirm reader stop. The service retains cleanup responsibility
until the exact terminal report or actual process exit; a cleanup poll cannot
restore consumed read authority. Revocation rejects new access and successful
handoff without forgetting an outstanding borrow. Physical release and semantic
admission remain separate even after full-byte verification succeeds.
`verify-completion-read` checks the exact terminal report and current custody
without releasing the physical borrow. Logical content/admission work can finish
under that holding; `finish-completion-read` performs release separately. Closing
custody between verification and release denies further verification and keeps
the allocation charged until the borrow is explicitly ended or the process exits.

`RetainedContentRead` revalidates stored typed rows against a newly prepared
common output contract. It uses the existing bounded typed decoder and canonical
encoder, keeps only row scratch, and compares the complete ordered CID, counts,
depth and value usage with the retained descriptor. Its receipt is content
admission, not proof that computation occurred. Registry/contract, target and
schema-width mismatches and declared over-budget metrics fail before reading;
changed content, order or metrics cannot finish successfully.

The installed managed-reader example connects custody to a fresh local process
without reopening the source DB or rerunning the producer. A delegated common
ledger reserves a separate read attempt and scratch before parsing; every received
chunk consumes transfer budget before typed acceptance. Physical full-body
verification and custody's terminal acknowledgment precede content acceptance.
The Node `process-readmission` assembly installs the common readmission verifier
internally; no request can provide or replace it. It snapshots the expected task,
origin and lease and enables exactly one opaque content receipt only after the
installed custody channel acknowledges that lease's verified full read. The common
bridge then checks the complete output contract again. Readmission permission is
revoked on cancellation/close, and the physical borrow is kept through this step.
The example can bind the output to an exact checked receiving port, but does not
start or resume that task. Its `completion-readmitted` response is diagnostic
metadata, not a serialized CompletedOutput, active reader grant or Program success.
Executing a subsequent Compute still requires its own common admission and budget.

Each successful completion has a fresh process-local identity, distinct from
its producer's bound owner. Verified representation conversion preserves this
identity and the output target; another execution with identical contents does
not. Rebinding a producer read to such a copy preserves the receiving port,
projection, input-binding identity and all original logical-use restrictions.
It does not depend on the old physical copy remaining available. Rebinding is
not a reservation or permission to replace an already selected DAG input:
selection, resource admission and exact request matching remain Host duties.

The common execution contract must not require an in-memory row table or cell
access. Local memory is one realization of the contract. Connector-specific
tables, filenames, sessions and processes remain behind implementation-owned
handles. A consumer which needs a row/column representation admits a metered
conversion candidate; inspection does not implicitly materialize a result.

The target local profile uses one execution process per physical Run instance,
with reuse between its tasks but no cross-Run process pool. Host-approved code
and a dedicated IPC session form the local trust boundary. Messages bind the
session generation, Run, attempt, selected request and owned output. This is not
cryptographic proof of correct execution or support for arbitrary remote peers.

The control Host retains authority over selection, reservation, completion,
holding attachment and cleanup. The execution side performs computation,
required value validation, canonical encoding and retention. IPC contains
bounded control messages rather than complete validation/result rows.

This profile ends at internal Host task completion, downstream consumer use and
cleanup. It does not authorize Program/Run success, formal Result publication,
Effect execution, or recovery after the control Host restarts. Existing Result
Artifact and Store admission semantics remain authoritative; local retained
files are not automatically durable Result Artifacts.

## Retention and loss

Outputs promising independence must have a verified independent holding before
normal completion. A retained file may supply that holding; a DuckDB table may
be an additional reusable copy. DB/task cleanup cannot revoke independent
completed results. Fragment-internal temporary values need not all be saved.

If only the execution process is lost, the surviving Host may admit a new
reader for an independently retained result, using the retained ownership,
evidence and ledger. It must not silently reexecute the producer. Failed tasks
remain failed/result-unknown; recovery of a completed result does not permit
continuing an otherwise stopped Program. Old-session reports are rejected.

A file path, stat result or claimed digest is not an immutable binding.
Retained-body publication and reopening must prevent or detect substitution,
truncation and mutation before granting successful consumption. File integrity
identity is separate from ordered logical identity. The physical framing is
private, schema-bound and versioned; it does not change canonical AoA/row wire.

For local process delegation the control-side Store creates and retains the
owned inode and capacity reservation. The installed writer receives a bounded,
single-use file lease bound to the actual IPC session. It opens the same inode
without following symlinks, streams physical bytes directly, and closes its
writable descriptor before reporting byte count and digest. The control-side
Store checks the exact lease and file identity/size; it trusts only the installed
writer for that digest and verifies it again on consumption. This storage report
is not computation, value-admission or canonical logical-identity evidence.

Cancellation keeps the delegated reservation until confirmed writer stop or
actual process exit. If a terminal byte report is lost, the granted write ceiling
is recorded as uncertain traffic, separately from confirmed bytes; reclamation
does not erase either counter. Completed independent files remain owned by the
surviving control Store when their writer exits. A new reader still requires
separate exact-result admission; file survival alone is not reader authority.

A delegated reader borrows the control-owned holding for one exact new session
and an independently generated read token. Its file descriptor is read-only;
bounded chunks remain provisional until the complete expected digest, size and
inode have been verified and the descriptor has closed. Only the matching
terminal report settles successful storage consumption. Revoking a holding
does not release an outstanding reader, and a report received after revocation
can settle the borrow but cannot authorize successful consumption. A failed
consumer can settle its confirmed stopped borrow without revoking an otherwise
independent valid body. These are physical storage conditions, additional to
the exact completion/producer admission required by the execution contract.

## Validation, encoding and budgets

All admitted types retain their existing precision, NULL and ordering laws.
Canonical value encoding belongs to the common MoonBit implementation, not a
new JavaScript semantic codec. A bounded batch sink can emit storage bytes and
the existing canonical digest together. Drained bytes are provisional until
encoding, required validation and storage admission all succeed.

Bounded batches do not excuse retaining every batch. Control metadata, queued
messages, open descriptors and indexes also require explicit bounds. Aggregate
byte/node/work limits persist across batches and strategy changes. Frame limits
are physical resource limits, not new language restrictions.

The common ledger reserves before work. The execution side enforces its granted
capacity at allocation/import/batch boundaries and pauses before requesting
additional credit. Logical obligations and physical usage are distinct. An
abort message does not acknowledge native stop or file removal. After a finite
Host-configured cancellation grace period, the owning Host may terminate its
Run's process; actual process exit settles execution resources, while retained
files and unconfirmed deletion keep separate cleanup responsibilities.

Full-source known-field validation, including values later filtered out, remains
required by the current acquisition contract. Native validation must preserve
failure precedence as well as rejection. Moving validation to the execution
side does not change its scope or permit trusting a bare success Boolean.

## Fusion and selection

Within one owned Compute fragment, compare legal fused/split realizations with
their compute, preparation, transfer, validation, identity, holding and cleanup
costs. Do not always choose maximal fusion. Intermediate join limits, demanded
evaluation, failure ordering and semantic ordering remain mandatory.

Task-to-task inputs remain completed and immutable. Reuse their physical
representations without unnecessary control-side roundtrips or reimports;
do not erase their required completion/identity boundaries. Cross-task fusion,
remote authentication, Control Host restart recovery and new language operators
are separate extensions.

Eligible profiles enter the normal candidate set without an experimental opt-in.
Only the selected realization runs: no shadow full-row validation/copy through
the old route. Unsupported profiles are excluded before work and explained;
old materialized or Local realizations remain explicit candidates. Failure after
start does not trigger an automatic fallback retry.

## Scan and holding inventory

| Boundary | Required fact | Current physical work to replace |
| --- | --- | --- |
| Source read view | Exact acquisition attempt and scan contract | Two-receipt full validation scan exported to control |
| Physical admission | Every required value satisfies its schema | All received batches retained before final guards |
| Native output | Required result/value bounds and ordered identity | Result exported again and converted to admitted rows |
| Canonical row identity | Exact existing ordered preimage | Hash traversal of retained complete batches |
| Completion | Verified exact output with independent holding | Trusted output verifier requires a full admitted row array |
| Producer admission | Exact port, live copy and consumer obligations | Cell-based input guard/demand walks on control-side storage |
| Resident reuse | Exact result/copy/resource generation | DB table supplements mandatory Host output holding |
| Named Result publication | Separate adopted admission/publication contracts | Not implemented by this physical Host profile |

The required facts remain. Full control-side transfer, duplicate storage and
repeated encoding are implementation choices, not normative requirements.
Measurements cover the entire chosen path, not only the hashing function.

## Construction and verification boundaries

`RetainedProducerScan` verifies the complete stored canonical row stream against
one exact live producer read without retaining the decoded rows. It decodes all
stored fields before applying the receiving port's projection, so omitted fields
cannot evade ordered source-identity verification. Returned row values remain
provisional until the complete scan succeeds. `FixedImportStream` converts these
bounded values through the existing DuckDB physical-parameter codec; it does not
construct a second full Local representation. Its successful content receipt is
not DB import evidence, a consumer guard/demand credit, or permission to start
SQL. Those remain required at their existing admission and execution boundaries.

Input guard measurement can attach to an empty exact retained scan. It consumes
the same receiving-column values used by import and the same cumulative physical
measurement budget later used for output. Memory inputs and retained inputs are
processed in receiving-port order. Output measurement cannot begin while an input
scan is incomplete; cancellation, identity mismatch or guard failure poisons the
measurement session rather than granting a fresh budget. Content verification
and measurement remain distinct from confirmation that a physical DB import
actually occurred, and comparison-demand accounting remains separately required.

For the supported fixed comparison, `FixedImportDemand` accumulates operand
demand from the same decoded input scan. It reuses the ordinary comparison
measurement laws and schema-lookup accounting. The installed import must match
the exact Compute; a verified full scan seals the input measurements. Normal
receiving demand admission then consumes them once, with the same value ceiling
and physical measurement limits, and accounts for the predicate using the actual
received output count. Deferred demand errors still reject the receiving result;
no cell-backed replay or budget reset is required. Counts/joins retain their own
demand contracts rather than acquiring a synthetic comparison predicate.

The fixed Node transport resolves a retained input through its exact opaque
material and installed Store binding, not by searching for equal content. It
inserts provisional rows into the isolated DB while the common input scan runs,
then checks full file integrity, canonical content, input guard measurement and
the bound demand state before making the native query available. Ordinary
cell-backed imports use the same transport and completion path. Missing retained
bindings fail rather than falling back to missing cells or an empty input.
Output receiving also requires completed input measurement. A successfully
completed Compute owns its independent retained result, so closing its original
capture does not revoke that result's later consumer.

`AdmittedOutputStream` owns cumulative admission and canonical-encoding limits.
Each drained batch remains provisional. Its final receipt proves admitted
content and exact encoding, not execution, storage, or a consumer's authority.
The Store must accept the exact bytes and confirm its independent holding
before an installed execution verifier can use the material at completion.

Retained native Acquisition reserves the file ceiling before any source or
Store work. After the installed transport seals the exact stream receipt and
attaches its live material, completion commits metadata capacity plus the
receipt's actual encoded bytes to the root holding. Unused reservation is
settled only after successful completion and root construction. Failed or
unconfirmed cleanup retains its remaining reservation; close retains the
committed holding until physical release is confirmed. Consumed transfer is
never refunded by this reservation-to-holding transition.

`TrustedRetainedOutputPort` is trusted implementation wiring, not an option
accepted from a Program or an execution request. Its verifier must establish
the selected attempt, input bindings, applicable obligations and settlement.
The common boundary also checks owned target/schema and live inputs before
publishing a result. Subsequently, upstream availability is not consulted to
revoke an independently completed result.

The Node DuckDB `runRetainedStrategyHostCompute` entry uses the existing selected
task, common reservation and atomic completion/holding boundary. It reserves
the file's maximum encoded byte size plus completion/schema metadata as retained
capacity; both must fit the selected envelope before Store or database creation.
An installed prepared execution may report its confirmed retained capacity at
completion. The common driver rejects a negative amount or one above its
original admitted capacity, then attaches the holding before publishing the
verified output. Omitted reporting retains the full admitted capacity. Reporting
does not discharge completion checks or release unused reservation on failure;
unconfirmed cleanup still owns both the holding and remaining reservation.
DuckDB's retained Compute reports metadata allowance plus the encoded size of
its exact verified, live staged stream material, not a caller-supplied size.
The attempt is fixed to streamed output and its admitted frame limits at creation
and rejects the full-row receiving entrance. For a prepared Compute without
value-sensitive join preflight, temporary execution capacity covers bounded
decoding/admission/encoding frames and completion metadata rather than cumulative
row/value counters. Those counters still enforce total execution work. The
smaller of this allowance and the established full-input allowance is reserved.
Value-sensitive join preflight retains keys across batches and keeps the
conservative full-input allowance; absence of an exact prepared plan does not
authorize the frame-only bound. Neither kind of reservation can be released
merely because cancellation was requested. The Node capacity projection and
common task admission use the same exact prepared plan. This is declared lifetime
accounting, not a measured peak-memory saving or a bounded-chunk RSS estimate;
native engine and transport allocations are reserved separately.
The Node transport's bounded profile requires both a delivered-row bound and a
frame-byte bound. Its allocation policy includes the pinned SDK vector window,
current parameter/metadata/result frames and one provisional scalar conversion.
Variable-width lengths are checked before SDK decoding; the connector refuses
unknown SDK layouts and oversized native chunks. These transport checks do not
replace cumulative value/work guards or promise a hard process RSS bound.
Retained inputs use bounded canonical-row decoding and the same typed physical
parameter conversion as fixed imports, without constructing a full Local copy.
File frames cannot exceed the receiving execution's framing allowance, and row
decode node/text limits are capped by its admitted transport scratch limits;
the source's larger limits do not authorize larger receiving allocations.
Result receiving cannot start before every exact input finishes identity and
required guard measurement. Retained join inputs remain subject to join preflight.
For joins without null-failure or cardinality assertions, that preflight checks
only shape: the exact admitted retained representation supplies its fixed row
shape without a full cell-backed copy. Owner, port, row/work/entry limits and live
input checks still apply, with the same measured preflight work envelope. The
subsequent streamed import independently verifies the entire content and guards.
Value-sensitive null/cardinality obligations are not discharged by shape alone;
they require the common key-stream validator described below. The shipped managed example
can execute retained A/B fan-in to an inner join and then group/count, preserving
all intermediate completion/identity and independent holding boundaries.

The common key-stream validator is a separate value-sensitive building block.
It attaches once to each exact retained producer scan and keeps only projected
join keys under cumulative row, work and scratch-entry ceilings. Keys remain
provisional until the full ordered content and attached input guard measurements
are verified. It then applies the same left-null, left-uniqueness, right-null,
right-uniqueness checks as the ordinary validator. Truncation, identity mismatch,
cancel or validation failure clears the provisional keys; successful evidence
still requires live exact inputs. This does not authorize SQL execution or
replace transport receipts. DuckDB attaches it to the exact import streams and
finishes it only after all input content and guard measurements succeed. Native
query readiness additionally requires the resulting exact join evidence. An
invalid join aborts the attempt without publishing a result or invalidating
independent completed inputs; physical cleanup remains separately confirmed.
Representation rebinding reprojects receiving columns by their checked names
under the original metadata admission limits. It must not retain physical column
indices from a different layout. A retained scan independently maps that view
to the stored schema's decoding order before guard, join-key or import use.

Capture-root allocation attachment likewise accepts the installed Host's
physical-release predicate. The common DAG keeps that exact predicate with the
holding: neither repeated attachment nor a cleanup refresh can replace it.
Logical close revokes new readers, but the allocation remains charged until
dependent consumers no longer retain it and the original predicate confirms
physical release. A refresh only polls; it does not acknowledge cleanup or
revive a closed output. Synchronous memory allocations need no asynchronous
release predicate. These callbacks belong to trusted Host wiring, not Program
input or completion-verifier configuration.

Closing a retained task revokes result use immediately. Its common holding is
not released until the Store confirms physical cleanup, including outstanding
readers. A failed close exposes the same retry handle; native stop alone cannot
erase file responsibility. The standard strategy entry does not infer a retained
representation from connector identity: representation-aware candidate/copy
selection is a separate admission responsibility.

`CompletedOutputImport` is an explicit representation conversion. It admits
values provisionally and checks the complete ordered identity against the exact
source result before exposing a Local-readable copy. Matching content alone
cannot acquire another producer's completion authority. The new copy retains
logical use restrictions, but does not inherit the original copy's physical
failure condition. Conversion reservations and the resulting holding remain
the physical Host's responsibility.

The inverse conversion serializes an existing completed cell representation
through the same canonical encoder. It reads the sealed row/column storage one
row at a time, with cumulative value/encoding limits and a bounded output batch;
it neither accepts replacement rows nor reruns the producing computation.
End-of-rows is not a complete receipt: the final delimiter and hash must finish
before the Store can seal its bytes. Storage binding requires the exact export
content receipt, not matching CID text from another export or completion.

Binding consumes the export token once and preserves the original completion
identity, input-binding identities and logical restrictions. The new retained
representation does not keep the old row store or borrowed producer buffers as
its physical payload. Its physical liveness comes from its own Store, and its
logical liveness remains the original result's. Provisional exports and tokens
release their source anchor on cancellation, failure or successful binding.
This conversion API does not reserve physical storage or publish a DAG task by
itself; an installed execution must include export/storage capacity and cleanup
in its existing common admission and atomic completion boundary.

File-to-Local conversion frames one bounded row at a time under backpressure.
The Store verifies the exact retained bytes before the conversion can finish;
the common decoder admits typed values without authoring-time normalization,
and the common importer checks the whole ordered logical identity. Explicit
NULL is a present value, not a missing field. Limits on raw row bytes, parsing
depth/nodes and scratch are separate from cumulative value/identity budgets.
A failed or cancelled conversion discards provisional memory without revoking
an independently valid source copy. Only a consumer needing Local cells pays
for the resulting complete memory representation.

The `retained_host_bridge` exposes only this common conversion protocol. It
does not interpret paths, DuckDB types or Node storage handles. The local Store
adapter owns bounded byte framing and integrity-confirmed reading; connector
wiring supplies the exact admitted source reader, never an execution-option
verifier. Building a Node configuration that uses conversion also requires
`moon build --target js --release src/retained_host_bridge`.

Private process messages are transport material only. Framing, session and
sequence validation do not grant permission to execute or publish. The Host
must bind the installed executor to common admission before starting it; it
must not serialize process-local opaque handles as purported execution proof.

An installed DuckDB Compute module can select canonical-file output before its
first estimate policy is prepared. That policy adds a distinct file-write,
seal and cleanup work slot and the file byte allowance to each fresh-DB offer.
Unknown file work remains unknown; it is not a free operation. The selected
dispatch retains the exact output mode and file ceiling. A row dispatch cannot
silently become a file dispatch, and a file dispatch cannot use a different
ceiling or return row-backed output instead. These checks precede reservation
and native work. Resident-table output is a different realization and is not
offered by this file-output policy.

The standard DuckDB contribution uses that same dispatch and common completion
boundary. Its pure `retainedOutput` transport setting fixes the Store location,
frame bound and canonical wire limits, without accepting a caller verifier.
Completed file output can feed the subsequent DuckDB input stream directly.
This does not provide implicit conversion for a Local consumer: a required
memory representation still needs an admitted, budgeted conversion. Installed
process-Store wiring can place those same outputs in a surviving control-owned
Store; plain file-output settings alone do not request that delegation.

Local's materializing execution uses the existing prepared-execution contract,
not the synchronous no-I/O contract. Its selected candidate remains bound to the
original receiving ports. Common start reserves both the Local execution budget
and a full-producer import allowance per non-cell input before reads begin.
The imported representation is accepted only after canonical identity checks and
exact completion/receiving-port rebinding; an equal-CID fresh computation cannot
substitute for it. Normal Local guard measurement and execution then use those
representations, while completion still matches the original input identities.

Imported memory is part of the result's retained allowance, not immediately
released scratch: a Local output can share its input buffers. Cancellation
discards provisional imports but does not imply the physical read stopped.
The installed reader must finish or stop before common settlement. Consumed
transfer remains charged. The Local contribution's asynchronous dispatch drives
these operations through the installed Store reader, then settles and completes
the exact common task. The synchronous entry rejects a materializing plan rather
than performing hidden I/O. Both entries are declared by the connector manifest;
the common Host does not inspect a Local execution variant.

An optional Local export policy adds independent file bytes and bounded encoder
scratch to the selected retention envelope, plus a separate supplied export-work
estimate. It uses the same prepared attempt even for cell-readable inputs; it
does not execute through the already-published synchronous path. After Local
computation, the original output is exported and bound to verified Store material
before common completion. An unsealed or unbound export cannot pass readiness.
Successful binding drops imported buffer copies that the independent file no
longer borrows. Logical output close and physical Store cleanup remain separate;
the attempt's original release predicate retains reservation/holding until cleanup
and normal consumer-retention checks permit release.

Portable Local dispatch imports only the abstract lease wiring, common Store
registry and bounded readers/writers. The Node process assembly supplies its
opaque Store configuration from `local-node/retained-process.mjs`; this concrete
file/process dependency is not in the Workers composition. Operator JSON cannot
construct that configuration or install an output verifier. The same task result
can feed either Local import or DuckDB import through the retained-input contract.

An explicitly installed Local import policy is frozen before estimates escape.
It adds a conservative per-input transfer/retention envelope and one separately
declared conversion-work estimate covering the task's imports. Actual start
reserves imports only for non-cell inputs; memory inputs are not copied or
charged as transfers. This bounded policy allows a mixed file-to-memory strategy
through normal selection, but is not yet a representation-aware prediction of
every upstream choice: its conservative comparison allowance may overestimate
conversions for memory-backed inputs. Unknown conversion work remains unknown.

Installed file representations register bounded read access with the Store
adapter. Receiving connectors see only a read contract and provisional bytes,
not DuckDB objects or file names. Registration is exact and non-replaceable for
that material handle; each read verifies its receiving port and availability
before and after consumption. Physical integrity and the receiving converter's
logical identity checks remain separate requirements.

The Node `serveManagedStrategy` execution assembly constructs the owning setup
inside its process and invokes the same `runCapturedStrategy` standard entry.
An installed application supplies pure preparation and an explicit `open`
operation; requests cannot choose a JavaScript module, implementation callback,
runtime or verifier. Preparation does not open the source. One process session
prepares once, executes once, and can release/retry confirmed cleanup; releasing
or failing never restores execute permission. Each task continues to use the
common engine's normal candidate, reservation and completion checks.

The assembly's reply is bounded diagnostic metadata, not a transferable
`CompletedOutput`, `ProducerRead` or result-publication grant. The caller must
not admit a retained result from that reply or interpret a successful release
reply as actual process exit. Surviving physical Store ownership and exact logical
result re-admission are separate contracts.
The example assembly uses the existing bounded
application profile; it does not expand frontend Program coverage.

An installed, bounded Host service permits the active execution request to obtain
Store resources after common task admission. Calls carry the exact process
session, Run, active request sequence and monotonic call number. No service is
available by default; installation snapshots its operations and cleanup owner,
and requires an explicit cumulative call limit. Unawaited, concurrent, foreign
or over-budget calls stop the channel. Awaiting a service does not turn a failed
or cancelled task into an unstarted task, and cancellation does not acknowledge
that started Host I/O has stopped.

The control-side process Store creates files lazily on the selected task's
reservation request, not during candidate enumeration. The execution-side writer
writes and hashes bounded bytes directly into the granted inode, closes its
descriptor, and returns a terminal seal report. Later consumers obtain exact
read leases; body bytes do not travel through the control channel. Common
canonical encoding, logical identity, completion and producer checks still run
in the execution process. Store reports alone have no logical admission authority.

Closing the execution-side output lease revokes its use and closes local I/O;
it does not delete the control-side holding. Actual process exit retires orphan
writers/readers but preserves already sealed independent bodies. Missing writer
reports retain conservative uncertain usage. The control Store has its own
capacity and cleanup handle; process-only capacity settlement cannot erase that
responsibility. This physical survival does not yet constitute result
re-admission into a fresh execution process or Host-restart recovery.

`createManagedProcessHost` binds process launch to a control-side common physical
ledger. Pure configuration validation and snapshotting precede reservation and
spawn. Each admitted launch consumes one provisioning attempt and reserves its
declared process-local retention and execution byte allowances. No other process
can reuse that reservation. Cancellation, failed replies and IPC disconnect keep
the reservation until the installed channel observes actual process exit (or
proves spawn never created a process). The exit observer releases capacity even
if the caller has not yet retried cleanup; the consumed attempt is never refunded.

These allowances are admission accounting, not an operating-system RSS limit.
For task execution, `capacity.childLimits` requests a delegated task ledger;
the process retention/execution envelope must cover its declared byte limits.
The process-only form without `childLimits` authorizes provisioning alone and
does not grant task execution to the managed example. Independent files require
separate Store reservations: process exit cannot release those files.

The common physical ledger supports an execution-domain delegation for this
connection. Admission reserves the entire child's planning, attempt, holding
and transfer quotas, plus a process-local byte envelope no smaller than the
child's declared byte limits. Provisioning itself consumes a separate parent
attempt. Other work cannot borrow the delegated allowance before a report
arrives. Cumulative reports are owner-bound, monotonic and checked before any
mutation; identical reports do not double charge. Only confirmed domain stop
permits settlement. An exact terminal accounting snapshot returns unused quota;
without one, the remaining quota is conservatively consumed rather than erased.
This accounting contract is trusted Host wiring, not result evidence or an OS
memory limit. It does not release separately owned Store files.

The private process handshake carries a snapshot of the delegated limits.
The installed strategy application constructs its real ledger from those limits
and exposes read-only limits and cumulative usage; the standard managed worker
checks the limits before allowing acquisition or dispatch. Program input and
diagnostic replies cannot install an accounting callback. Usage messages are
bound to the session, Run and current request sequence and occur at most once
per request, followed by at most one terminal report after stopping. The control
channel applies each report through common ledger validation. A terminal report
alone does not release process capacity: actual exit is still required. Failure
to receive an exact terminal report, including a failed finisher, consumes the
remaining delegated quota conservatively on exit. Cancelling an unstarted spawn
is distinct and can return all child allowance without inventing child usage.
Unreported transfer quota becomes `uncertain_transfer_bytes`, not confirmed
`transferred_bytes`. Both reduce future transfer headroom; cleanup cannot refund
either. Planning/attempt/holding counters are consumed quota counters, while
uncertain traffic remains separately visible from measured transfer volume.

Configured native acquisition fixes validation-scan hashing and demand budgets
before receiving metadata. Each admitted chunk is measured and hashed, then
discarded; only bounded accounting and the final digest survive. Both receipt
identities still use their exact canonical typed-row preimages. Validation
record measurement shares its cumulative allowance with native output, while
operand-demand measurement has its own fixed allowance. Neither can be reset
after discarding the scan.

Value-guard, demand and digest errors remain deferred to their established
validation boundaries. A later physical value error must not be hidden by an
earlier deferred guard failure. This removes retained validation batches, not
the required full-source validation scan, transport into the executing adapter,
or the independent native-output holding obligation.

The retained native-output receiver drains one admitted physical batch into
bounded canonical text and releases that batch before accepting another. It
does not expose row-backed materialization as an implicit fallback. Both
receipt digests remain subject to their combined budgets, and output encoding
failures remain deferred until the preceding physical, value and demand checks
have run. Failed streams expose no successful content receipt.

Before native capture, the installed Store must bind a live independent holding
to that exact receiver's content receipt. The normal acquisition issuer still
verifies the selected attempt, read view, transport settlement and obligations.
Common completion then seals this observation and material together. Subsequent
logical revocation follows the observation, while physical availability follows
the chosen copy. Explicitly converted Local storage is not revoked by loss of
the original file, but still observes closure of its logical acquisition.

The Node retained acquisition entry uses the same source transport and issuer
as the row-backed entry. Files are finalized before capture is exposed; failures
retain both native and file cleanup responsibilities. The accounted retained
entry reserves evidence/schema metadata and the exact maximum file bytes as
retention on the DAG's ledger before native work. It fixes output streaming
inside that entry, before exposing the attempt; the smaller retained allowance
cannot be used with the row-materializing path. Temporary capacity covers bounded
transport decoding, cursor/value conversion, streaming encoders and evidence
construction. The Node boundary preflights each encoded column frame against
its byte/node/row ceilings; both streaming receipts enforce the configured row
bound. Its output buffer cannot exceed that same byte ceiling, checked before
reservation or attempt creation. Cumulative row/value/identity counters remain
enforced but do not stand for simultaneously retained batches. This is a declared
capacity policy, not an OS or V8 RSS guarantee. The non-streaming entry retains
its original capacity model. Completion
attaches the allocation before the captured root is available. DAG adoption
transfers that exact holding and its original physical-release predicate,
without opening an untracked parallel output port.

Native stop settles execution capacity separately from file release. Capture
close revokes new readers immediately, while the allocation remains charged
until cleanup is confirmed, including when adoption never occurred or streaming
failed before capture. Explicit cleanup refresh cannot replace the original
predicate or refund consumed transfer. The configured process assembly can bind
this same acquisition to the control-owned Store as `capture-0`; both the
capture and subsequent retained Compute bodies survive execution-process exit.
Its Local import policy is explicit so that a Local candidate can consume this
non-cell input through the same representation contract. A fresh installed
reader can separately re-admit retained content under surviving completion
custody; that is not permission to resume a Program or start another Compute.
The reader snapshots the receiving profile's metadata limits, including column
count, independently of the supplied completion descriptor. Its content counters
remain cumulative, while row decoding and its pre-read scratch reservation are
bounded by the admitted frame. Exact consumer projection matching uses the
configured metadata-work ceiling rather than a small example's fixed budget.

The Node storage/framing/process lifecycle tests run with
`npm run check:retained-boundary`, independently of DuckDB installation.
Control-side process reservations are checked by `npm run check:process-capacity`,
which builds the connector-independent JS bridge with the pinned MoonBit toolchain.
Common admission, encoding, conversion and completion tests belong to the MoonBit
three-target checks. These component checks do not substitute for standard
Host, native acquisition, real DuckDB or end-to-end performance acceptance.
