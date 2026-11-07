# Python Local in-process Host boundary

The Local adapter invokes MoonBit directly through Wasmtime. Node is a build
tool, not a runtime dependency or a transport fallback. The public Client wire,
remote-site protocol and in-process ABI are distinct contracts.

## Transfer custody

`client_host_buffers` composes the existing physical resource Ledger's shared
capacity, allocations and borrows. A pool reserves its allowance once. A transfer
charges both mutable staging and immutable wire payload capacity, including the
overlap during sealing, plus the physical adapter's copy allowance. All live
transfers share that allowance; byte equality does not merge allocations.
Reservation issues custody before allocating the large staging array. The
first admitted fill allocates storage under that existing reservation, so a
trap during transfer still leaves the caller's exact handle available.

The source decoder preserves raw JSON strings and keys, including Unicode and
NULL. It distinguishes parsing limits from malformed input. Sealing a transfer
does not check a Program or admit a Run.

Store observation retains exact raw rows in unsealed input loans. A stored CID
reference is raw address text, not a JSON document. These loans expose no parsed
source-node capability. The separately bounded closed observation envelope quotes
those unchanged bytes and is sealed before the existing Core checks its scope,
references and complete stored chain. Both raw rows and the envelope use in-order
fills of at most 16 KiB. Failed transfer keeps the original loans and workspace;
closing them neither repeats the Store read nor acknowledges a durable commit.

An allocation is retired before cleanup. Readers must acknowledge physical stop
before their exact borrow is returned. Failed stop or cleanup retains the same
handle and allocation for retry. The pool's reservation is settled only after all
allocations are released. Closing a pool blocks further admission immediately.

## Public Local Check reporting

The ordinary Local transport routes `Client.check` to the existing Common
authoring checker. It does not infer a public verdict from preparation counts,
exceptions, a Run admission or physical execution. A Check never reserves a
Submission, runs a Task, reads Source rows or starts Compute, Model or Effect.

The private scalar ABI 77 `actql_check_*` child retains the original installed Environment,
current Host configuration and captured request loan before entering the
checker. Metadata and report production are one-shot calls with independent
output custody. Both recheck the same physical Host before and after Common;
the Python copy remains inside that original entered observation. Parent
configuration and Environment close refuse while any such child is retained.
Partial production and failed output/input return retain their exact handles
for explicit child-first cleanup, including after an interrupted invocation.

The trusted Python reporting adapter issues keyed, role-separated revisions of
exact received bytes and a keyed context reference. The context binds the
actual compiler, both generated reporting schema identities, audience,
connection, requested scope, admitted public policy/profile selections and
visible aliases. The Common metadata projection omits the private Environment
CID and hidden Source inventory. A missing Source publication supplier exposes
no aliases and provides no complete-namespace proof; protected resolution stays
unresolved rather than becoming proof of absence. None of these reporting
references grants permission or authorizes a later Run.

The existing SDK validates the returned schema and binds diagnostic locations
to the captured input. The Local bridge additionally checks context, scope,
document roles, revisions and byte lengths against that invocation. Completed
reports are bound by that metadata; failed and unavailable outcomes also retain
the original attempt correlation. Response transport has a separately bounded
Check allowance while preserving the smaller existing metadata-response limit.
It does not turn a report into a reusable checked Program or bypass ordinary
submission checking and current authorization.

When an in-process Local submission loses its response or refuses its response
wire, the SDK's existing Unknown carrier retains the same underlying Local
failure for diagnosis. That reference supplies no retry or nonexecution proof.
Remote transport diagnostics remain private, and cancellation retains its
original carrier rather than becoming Unknown.

## Durable SDK Run observations

Fresh Local acceptance issues the existing observation counter/key marker in the
same submitted ready row as its original Run admission. The accepted Run/control
revision remains separate. Historical marker absence remains unavailable; it is
never interpreted as a new zero counter during lookup or restoration.

The Wasm SDK observation port uses the original complete stored publication,
current Run-read authority and current Sealed payload/reader bindings. The
retention Owner independently selects availability. These observations create no
Result-read grant or delivery attempt. The lower publication observation port
continues to report unknown availability when those independent facts are absent.

The existing RunState observation Owner derives the semantic key and bounded
revision from the same retained submitted row. A changed fact proposes one
metadata CAS; a clock-only reobservation reuses the exact saved original. The
physical Host validates the prior row inside the fenced transaction and rereads
the exact committed successor before exposing public wire. A lost response keeps
the same input/output for lookup and cleanup; it never repeats that write or
dispatches the Run. Parent close remains BUSY during an active state callback.
Saved-row confirmation, the final original Run guard and response transfer share
the same entered physical journal snapshot. Leaving that snapshot does not make
its normal current guard usable later; a refused guard retains the same output
and cleanup duty without exposing the candidate response.

Private scalar ABI 75 adds the SDK observation preparation, prior-row validation
and saved-row confirmation entrances. Their generated declarations and compiled
module must agree. The Client wire and journal formats retain their existing 0.1
contracts, including legacy absent bytes in the generic row encoder.

## Instance-private Wasm facade

The physical adapter installs one fresh positive instance nonce. It supplies
positive physical input identifiers that cannot be reused while live. Core
issues monotonically increasing handles from a shared sequence for input and
reader kinds. Handles are never serialized Client references, durable operation
identities or execution authority. The adapter must keep handles private to the
owning instance; neither a handle nor a nonce is an authorization token.

The Python physical bridge checks the installed artifact digest, scalar ABI
version, exact callback signatures, required exports and linear-memory maximum
before opening the instance. `actql_host_abi_version` is declared by `src/client_host_wasm/version.mbt`;
`scripts/generate-local-wasm-abi.py --check` verifies the generated wrapper
declaration. This private ABI version is independent of Client wire and package release versions. Optional
Wasmtime import is deferred until physical Local construction. Remote import
does not load Wasmtime or DuckDB.

The transfer allowance must fit a positive signed 64-bit ABI value; instruction
fuel must fit a positive unsigned 64-bit Wasmtime value. Reject out-of-range
Python integers before loading the engine. Foreign conversion must not wrap a
configured capacity or fuel budget into a different value.

Calls into an instance are serialized. Physical callbacks cannot reenter it.
Input loans belong to their exact bridge object; copying a loan or using it in
another instance cannot acquire custody. Python retains immutable bytes and
measures their copy allowance before transfer. Only an explicit physical
callback returning true acknowledges stop or cleanup; exceptions retain pending
custody. Failed close keeps the same instance and its reservations for retry.
The bridge retains a successful physical cleanup fact until Core acknowledges
retirement. A trap between physical completion and its acknowledgement cannot
repeat cleanup. Acknowledged input close discards its private loan and completion
record; repeated transfers do not accumulate released descriptors.
Closing this Host bridge is separate from closing a Client connection and
cannot decide Run cancellation.

### Child-process lifetime of native allocations

A joined native thread has stopped using its thread-local payload; it has not
retired its process. Rust and platform runtimes may retain process-static
allocations after every handler thread has joined. Such an allocation remains
in its original physical holding. Allocation-level `try_close` and domain
borrow return continue to refuse while it remains live. Engine close, thread
join, a cancellation request and observation of an absent PID cannot turn that
retained responsibility into a released holding.

An exclusively owned child region has a distinct physical retirement boundary.
Before child startup, the existing process Owner retains the original child,
channel, region, lease and backing correspondence. Its scoped stop observation
must confirm that the original execution and IPC users have stopped. The
original mapping and descriptor cleanup must then actually complete before
that region's borrower can be discharged. This does not individually free a
process-static allocation, reset its allocator header, make unused quota
available, or authorize another child to adopt the region.

Failed or uncertain stop, unmap, descriptor close or acknowledgment retains the
same original responsibility and partial-cleanup carrier. A completed physical
cleanup step is retained and is not blindly repeated after a later failure.
Foreign child, region or lease observations cannot retire the original region.
The process Owner's stop pin remains held through physical cleanup; an exit
code or PID alone is not a substitute for that original scoped observation.

Ending a parent transport borrow is a separate, earlier restriction. The same
channel first prevents new I/O and physical-current observations and restricts
its Common child frame. Its serialized physical caller must finish actual
in-flight uses before returning the original endpoint borrow to the FD Owner.
Metadata, original frame, Unknown outcomes and backing custody remain retained.
The FD Owner may then confirm its own child stop and descriptor closes. Neither
the restriction nor borrow return acknowledges that stop, metadata retirement,
mapping cleanup, final quota settlement, or the Run's business outcome.

The same process/channel association admits only the original scoped Holder's
opaque endpoint borrow and the channel's original Common frame. Descriptor
numbers are checked only for physical correspondence after that nominal check.
The association excludes a parent Root/Reader context in the child's domain.
Generic domain-current access remains refused; only the associated channel
reuses its same Common projection under the original process/borrow checks.
The child identity comes from that Holder, not a supplied PID.

After confirmed process/IPC stop, the original region/FD and stop-pin closes
are remembered independently of Common reporting, reservation and metadata
retirement. A later reporting or cleanup refusal retains the same carrier and
its exact child issue, including Unknown. Retrying that cleanup does not repeat
unmap or pin close. Parent registrations and reverse references are removed
only after their corresponding retirement acknowledgments; this connection
does not recreate a child Ledger or refund uncertain parent quota.

Physical region retirement is separate from conservative quota reconciliation,
Common borrow settlement and the Run's remote or business outcome. It does not
prove that an external operation was never sent, acknowledge a commit, permit
automatic resend, or supply missing ordinary runtime funding.

The private payload-request projection borrows one original completed Result
publication and its exact physical input. The input contains only the Store
authority CID, material generation CID and payload byte ceiling. The existing
Core payload Owner derives the schema, order, logical Result, exact byte count,
row count and original publication attempt. This projection does not write a
payload, install a Store, authorize a publisher or acknowledge durable commit.
Current Run and Source authorization is checked before each production call,
including reuse of a completed projection. Its output is bounded to 65,536
bytes; cleanup failure retains the same child, parent pin and input borrow.
The parent refuses close until that child is released. Retiring the earlier
preflight transport output preserves the original semantic preflight used here.

All exports use scalar arguments. Input chunks are ordered, at most 16,384 bytes,
and admitted before the physical callback runs. Input imports are
`actql_host.input_byte`, `input_cleanup` and `reader_stop`. Native physical facts
use distinct `native_settled`, `native_stopped` and `native_cleaned` imports.
Only exact boolean true is acknowledged; unknown handles, exceptions and truthy
values remain pending. Stop or cleanup does not imply a committed read view,
and a committed view does not imply stop or cleanup. Bytes must be in
0..255. Cleanup and stop return zero only when the corresponding physical fact
has completed; nonzero retains custody. Adapters must convert physical failures
to pending results rather than destroy the instance holding cleanup obligations.

The `actql_buffer_*` exports return zero for completed actions, positive handles
for reservations and borrows, or these negative outcomes:

| Code | Meaning |
| --- | --- |
| -1 | Foreign instance |
| -2 | Missing, stale or wrong-kind handle |
| -3 | Invalid configuration |
| -4 | Capacity refusal |
| -5 | Closed or unavailable transferred bytes |
| -6 | Invalid chunk position |
| -7 | Incomplete transfer |
| -8 | Malformed JSON input |
| -9 | Physical stop or cleanup pending |
| -10 | Other typed Ledger refusal |
| -11 | Input, node or depth parsing budget exhausted |
| -12 | Invalid physical byte |

Usage exports return signed 64-bit byte counts, or -1 for a foreign instance.
The module's linear memory has a 16 MiB maximum. This bound and the transfer
pool's payload allowance are separate limits. Transfer accounting alone does
not account for parsed object metadata, the complete Wasm heap, Python retained
objects, DuckDB workspace or aggregate Local execution. A product Host must
reserve and account for those resources using their existing Owners before
claiming an aggregate execution bound.

`open_pool_on_ledger` composes the existing transfer pool with an installed
Host root Ledger. Its shared reservation competes with the same root's
workspace and other pools before transfer allocation. Closing the pool settles
only that pool's lease; it cannot return another workspace reservation or hide
another pool's cleanup. Failed cleanup retains the same root reservation and
allocation, including when independently valid concurrent pools exhaust the
aggregate allowance. Standalone `open_pool` uses the same implementation with
its own bounded Ledger. This composition hook does not establish that all
product components are already connected to the root.

`reserve_workspace` reserves the configured physical allowance on that same
existing Ledger before physical allocation. `close_workspace` marks cleanup
pending, then waits separately for physical stop and physical cleanup. It
retains the same loan/reservation on either failure and remembers successful
observations, so settlement retry does not repeat physical cleanup. Logical
Compute completion, cancellation requests and transfer-pool closure cannot
return this allowance. The trusted physical adapter must supply observations
of the exact reserved workspace; this binding does not authorize I/O or imply
that the product's complete runtime footprint has been accounted for.

## Validated commit material view

`PublicationCommitPreparation.finish_view()` retains the original complete
validated chain under the existing preparation. It exposes one immutable
contract at a time, in fixed root order followed by the six original inventories.
The view does not copy or re-admit contracts, create an index, authorize a
publisher, install Store data, or acknowledge durability. The existing `finish()`
continues to return only validation completion and releases its inputs.

The active view reserves one descriptor within the original workspace ceiling.
Count and ordinal selection inspect a fixed number of inventory boundaries;
they do not scan inventories or contract bytes. Validation still advances through
the existing bounded cursor and retains its quantum-independent logical work.
Borrowed arrays must remain unchanged until the original view is released.

Cancellation immediately refuses further view reads while retaining the same
original inputs and descriptor. Physical output use and input borrows must stop
and cleanup must succeed before the private Host calls `release_view()`.
Cleanup failure retains that same view for explicit retry. Owner identity and
the exact nominal view are checked; foreign or copied views cannot read or
release originals. Successful release removes the input references and owner
back-reference, retaining only the retired nominal token for idempotent cleanup.
A later read, new finish, or cursor advance remains refused.

The private Wasm publication parent retains this view after its existing commit
finish operation. Candidate transport reads the original request, attempt and
nominal index from that completed cursor, after the existing current Run/Source
check. Parent close first waits for its output children, then follows the
original commit-input stop, parent-output cleanup and Source/input stop order.
Only successful completion of those steps releases the view. A failed step
keeps the same parent, input custody and cancelled view for explicit cleanup
retry. No new export, scalar ABI version or Client wire field is introduced by
this custody connection; it is not a complete material transport or Store ACK.

## Physical DuckDB boundary

The private Python adapter loads an explicitly installed standalone DuckDB C
library with a verified digest and selected version. It neither discovers a
Node package at runtime nor falls back to the Python extension's unbounded
row-fetch APIs. The existing native adapter's C layouts and scalar row/field
codec are shared boundary references. Canonical environment settings are
generated from `adapters/connectors/duckdb/environment-contract.json`.

The selected physical C API and by-value layouts are generated from the
vendored DuckDB header by `scripts/generate-local-duckdb-binding.py`.
`scripts/local-duckdb-c-api.json` selects existing operation names and the
existing library-version string copy; it declares no query capability or new
library compatibility. Other returned text pointers remain borrowed and
length-aware. Generated field names follow the C header, while the independent
pre-generation vector fixes scalar widths, order, alignment and nested layout.
Actual C layout checks and selected-library executions qualify that header,
Python wrapper and library together. The C header version, selected dynamic
library version, private Local ABI and Client wire version remain independent.

Before opening a database, the product Host must reserve the native workspace
through the existing Core resource Owner. The adapter applies a memory limit,
one worker, disabled external access and extension loading, and no temporary
spill. These physical settings alone are not an aggregate memory guarantee.

SQL arrives from the existing checked acquisition Owner. The physical adapter
does not parse, authorize or repair it. The private physical binding profile accepts the existing Core BOOLEAN,
DOUBLE and VARCHAR projections, including explicit NULL. DOUBLE is transferred
using the existing sixteen lowercase hexadecimal IEEE-bit payload; text uses
length-aware binding and preserves Unicode, CR/LF and embedded NULL. DATE,
TIMESTAMP and DECIMAL binding are not yet supported by this physical profile.
These capabilities must be checked before product dispatch. Missing parameters
are a count mismatch, not NULL or a default value. Unsupported native types are rejected before rows
are fetched. Core remains responsible for pre-execution Capability admission.

Row and metadata encoding writes only into a bounded, caller-reserved bytearray.
Native VARCHAR length is inspected before any Python cell copy. JSON escaping
cannot grow that buffer, numeric payloads follow the existing native codec,
and raw Unicode, embedded NULL and line endings are preserved. Parameter input
is an immutable tuple of at most 32 scalar projections. Each text copy is
counted in UTF-8 before allocation against both the cell ceiling and the
remaining shared parameter-copy allowance (the row-byte ceiling). All payload
checks precede native preparation; exact native arity and binding checks
precede execution. The product reservation must account for simultaneous Core
input, Python encoded parameters and DuckDB-owned parameter copies. A capacity
failure does not deliver a partial row, claim EOF or authorize a repeated query.

For the existing Native receipt decoder, `read_column_row` writes one-row
column vectors directly into that same reserved buffer. For example, native
row `["7",null]` becomes `[["7"],[null]]` with a claimed row count of one.
No intermediate parsed row or transposed copy is retained. Both framing
methods consume the same native cursor and share its row and byte ceilings.
The existing Core receiver validates column shape, counts, schema, values and
cumulative limits; the physical encoding does not certify a Source receipt.

`begin_read_view` retains one physical transaction on the same connection used
for metadata, validation and processed-result queries. The fixed transaction
control commands do not introduce a query parser or authorize Source access.
Only a successful observed COMMIT sets the physical `committed` fact. All query
streams must release their exact native handles before commit or view teardown.
The Core Native attempt Owner still decides whether that settled view belongs
to its issued attempt and whether the receipts establish a capture.

A missing control reply is not settlement or permission to repeat the command.
Failed BEGIN/COMMIT/ROLLBACK retains the same read-view and result handles. After
result cleanup, disconnect physically terminates an unresolved view without
replaying control I/O. Closing a readable, unfinished view rolls back once;
rollback never reports commit. A known COMMIT survives a later result-cleanup
failure, while connection release remains pending until the result is actually
destroyed. Busy I/O or failed destruction retains custody for the same-handle
retry. Read-view close is physical cleanup, not cancellation of a Run.

Statement, result, chunk and logical-type handles belong to the exact physical
connection and stream. Copied handles are refused. Interrupt delivery is not
physical-stop acknowledgement or a Run cancellation result. While native I/O
is active, close remains pending; failed destruction retains the same handles
for retry. Closing a connection waits for its stream custody to settle and
never starts another query or decides a Run outcome.

## Execution boundary

The `actql_program_*` source-free preparation profile installs a trusted Check
Environment through its existing canonical-wire Owner. Its environment handle
holds the configuration's exact buffer borrow. `prepare` selects structured JSON
or an AQL string explicitly and invokes the common frontend and Checker. AQL
retains the lowerer's parsed Program and authored provenance. There is no syntax
fallback, fabricated parameter value or physical Source lookup.

A preparation handle is reserved and returned before invoking the Checker. It
retains the original input borrow, its environment handle and the Core's typed
success or rejection. An interrupted invocation remains reachable for cleanup
under the already-issued handle and is not silently repeated. -23 means the
invocation has no completed typed outcome. Environment close is pending while
any dependent preparation is retained. Preparation close returns its exact loan
only after the physical callback acknowledges stop. Rejected preparations have
the same custody obligations. Root close retains capacity while any loan or
cleanup remains pending.

The private `prepared_results` and `prepared_tasks` exports project inventory
only from a prepared Core value. -22 means that the retained typed preparation
has an error; it is not a public invalid/undetermined classification. -20 rejects
an installation configuration and -21 rejects an input of the wrong ABI kind.
The public diagnostic projection must use the retained Core reason rather than
infer a verdict from these readiness codes. This source-free profile supplies
no bindings and grants no Run admission, execution or Result access.

Run admission, checked task progress, publication, cancellation eligibility and
durable recovery remain MoonBit Owner responsibilities. Python provides physical
callbacks and persistence, not a second Run or recovery state machine. This
transfer facade provides no task dispatch or durable recovery start.

## Checked task Host

The single-Source relation profile defines its Run before acquisition using the
same request, compilation and publication Owners as the source-free profile.
Neither profile grants physical Source access. Unsupported Graph/Model/Effect
paths remain outside this installed profile.

The existing physical-start Owner's accepted decision is retained against the
exact plan before Source I/O. The verified capture is then borrowed by the
existing captured Local Host. Compute binds that retained decision rather than
claiming the Run is still physically unstarted after acquisition. A decision
from another plan cannot authorize this Host. Current authorization is still
checked at each task activation.

The private `actql_run_reserve_physical_start` scalar entry retains one exact
immutable fact loan and the installed current account configuration against the
original Run handle. Its closed object contains the original request record,
`definition_cid`, and explicit boolean facts `reserved`, `physically_unstarted`,
`cancellation_requested` and `pre_start_failure_confirmed`. Missing or NULL
facts are malformed physical Host input, never false or a default value. The
physical adapter must obtain these facts from its durable original journal and
resource reservations; neither a Client payload nor preparation can supply
proof that they are true.

`actql_run_confirm_physical_start` admits the retained request through its
existing codec and calls the common Run start Owner under current subject-bound
authorization. The input loan and Run remain live during an interrupted call.
One original Run handle reserves at most one start invocation, including after
that invocation closes. A known result may be observed again without redoing
the evaluation. Unknown, interrupted or malformed invocations cannot silently
replace their facts, reserve another start or imply unstarted physical work.
The readiness status is not a durable Submission response or evidence that I/O
was dispatched. Closing this loan requires physical reader-stop acknowledgement
and does not cancel or rewrite the original Run.

Captured root inputs and completed Compute producers use the existing managed
driver's distinct input variants. The common compute Host refreshes its normal
estimates/selection before dispatch; no Python task counter or replacement
selector is introduced. Source capture custody outlives its consumers, and
closing Compute does not revoke the caller's acquisition Owner.

`configure_captured_source_local_compute_on_ledger` routes the single verified
capture through the same existing captured DAG and retained Compute driver
using the installed Host root Ledger. The Local Host does not create another
Ledger for this path. Transfer pools and independent Host workspace can remain
reserved on that root while tasks run. Task/output cleanup settles its own
reservations; it neither returns the workspace lease nor fabricates cleanup
for another component. Run and per-task authorization checks remain required.
The existing two-Source path retains its exact prefix and binding checks.

`configure_local_native_source` binds one existing checked query requirement to
the installed physical database/schema/table and its read account, access tuple
and context. The configured Native candidate requires the existing registered
receipt Capabilities; publication or a general Allow entry cannot manufacture
them. The caller principal must match the original Run, while physical read
authority remains separate from Run activation authority.

`start_local_native_source` requires that exact plan's retained pre-I/O start
decision and a current Acquisition permit bound to the requirement CID, read
tuple and context. Revoked authority, a different database, another requirement
or another Run's start decision is refused before an attempt is issued. The
existing Native acquisition Owner alone validates metadata, both receipts and
the settled read-view observation. The installing Host must retain the issued
attempt and durably record its physical invocation; these in-process adapter
values neither reserve the whole runtime nor establish process recovery.

The private `actql_source_reserve_configuration` entry retains the installed
physical configuration loan against the original Run. `actql_source_configure`
selects its explicit checked `stage` and `source_index` through the existing
query-requirement Owner; no frontend or Python pipeline scanner derives another
query. Its closed object carries the installed engine/receipt contract bodies,
database schema/table, read account/tuple and context. Optional fragment and
ordered contract bodies may be absent; explicit NULL is malformed configuration
rather than an absent contract or a query value. Core admits all supplied
contracts and the registered receipt Capability before configuration is ready.

An interrupted or malformed configuration cannot silently invoke its constructor
again. Its borrow keeps both the original Run and input alive until physical
stop acknowledgement. Configuration readiness performs no physical database
operation, reserves no Native workspace, and grants no read or completion
authority. Native invocation, both receipt streams and the exact settled
read-view callback remain separate from configuration readiness.

One original Run handle reserves one Native configuration, and that
configuration reserves one attempt, including after either closes. The private
`reserve_attempt` entry retains the exact accepted original Run-start token and
an immutable current-read-account/attempt-nonce loan before construction can
trap. `start` delegates current read authorization and issuance to the existing
Owners. Its settlement verifier accepts only its exact issued Native attempt
and the trusted physical read-view fact for that private handle. Another
attempt, a Run activation permit or a fabricated completion cannot substitute.

`actql_source_accept` admits one closed physical event at a time under the
current read account: kind 1 metadata (`rows`, `fields`, `columns`), kinds 2/3
ValidationScan/NativeResult begin (`fields`), kind 4 chunk (`rows`, `columns`),
kind 5 receipt finish, and kind 6 completion. All envelopes also contain
`read_account`; fields/columns use the existing bounded physical codecs.
Existing Native Owners enforce receipt order, schema, counts, values, limits
and exact settlement. Malformed or refused events abort that attempt rather
than allow a later valid chunk to hide the rejected input. An interrupted
event leaves its invocation pending and its input borrow retained.

`close_event` only retires the already evaluated input borrow after physical
reader-stop acknowledgement; retry never evaluates that event again.
`completed` reports Native receipt completion, not Run success or publication.
Attempt close blocks further events, waits for actual physical stop, closes its
Native Owner, and then waits separately for physical cleanup and both input
borrow retirements. Failure retains the same handle and parent loans. Run,
configuration and start-token release cannot bypass those obligations. The
Host must still reserve aggregate workspace and durably record physical query
invocations before using this connection for execution.

The private Python bridge registers settlement, physical-stop and cleanup
observers against the exact issued attempt before its start call. It retains
those observers and the same identity-bearing loan until Core acknowledges
retirement. A copied/foreign loan cannot start, feed events or close the attempt.
Pending cleanup and trapped calls retain custody; neither invokes a replacement
attempt. Receipt completion is exposed separately from the Run outcome.

`reserve_command` retains current account input and reserves a 100,000-byte
output allowance before `produce_command` emits the existing Core Native SQL
and prepared physical parameters. Command kinds 1/2/3 project metadata,
validation and processed-result queries. The shared parameter codec preserves
type identity even for NULL; the initial installed Python binding profile is
BOOLEAN/DOUBLE/VARCHAR. Unsupported native parameter types are refused before
physical Source I/O. Python consumes this closed projection with its shared
JSON admission and existing physical binding adapter; it does not parse,
lower, repair or rebuild SQL.

An output-reservation refusal still returns the issued command custody handle
when its account loan already exists. Producing that handle reports the retained
reservation refusal. Output cleanup, including an unallocated registered
physical destination, completes before account-borrow retirement. Cleanup
failure retains the same descriptor quota and parent attempt, and successful
physical cleanup is remembered if later input-stop acknowledgement is pending.
Interrupted production cannot silently produce again. Projecting or reading
these bytes is neither physical dispatch nor permission to resend them.

The private Python bridge keeps command and Run-material output loans distinct.
Both use the same bounded byte-copy and cleanup implementation; cross-family,
copied and foreign loans fail before Wasm I/O. Command reservation registers the
physical destination before entering Core, and a refused issued reservation
remains available for retirement through that exact loan. No partial copy is
cached as a command, and a Core trap does not automatically invoke it again.

`client_local_run` installs the existing retained Local compute driver for a
checked source-free plan. Configuration opens task Owners and resource accounting
without physical dispatch. Registry, Values, ordered derive and expression
fragment bodies are admitted through the existing engine contracts. The existing
registry generator supplies these bodies to the focused Core consumer; expected
rows remain independently authored.

Before the first task activation, the physical Host must supply the original
durable request, definition identity, reservation, physical-start and cancellation
facts to `confirm_local_compute_start`. The existing Run start Owner decides
whether those facts permit work. Its accepted result is retained as an opaque
`LocalComputeStart` bound to the exact configured Host. Configuration alone,
another Host's decision, or a cancelled/pre-start-failed request cannot authorize
task dispatch. These in-process values do not constitute durable journal records.

Every `start_local_compute_task` matches the original subject, account, access
tuple and context against the current authorization. The checked DAG supplies
the next task and exact producer occurrences; the managed driver checks the
completed input materials and resource obligations. Activation consumes the
existing task Owner's exact revision-bound, single-use grant. The authorization
Owner projects its already evaluated dispatch action; callers cannot manufacture
the read-only action constructor. No Python task counter or recovery decision is
introduced.

Managed operations retain their existing quantum, finalization, stop and cleanup
interfaces. Their retained outputs remain charged until those Owners release
them. A missing next task proves neither public Run success nor Named Result
publication. Durable admission, publication storage and restoration of completed
materials must be connected separately before the ordinary Python Client can
advertise Local execution.

## Physical persistence

The private Python `LocalByteStore` provides opaque byte storage and an atomic
compare-and-exchange. It does not decode Program, Submission, Run, task or Result
records. The existing Core must issue and re-admit their closed records, original
identities and transitions. A missing physical row is not a Source absence fact
or permission to retry an operation. A store generation is only a physical CAS
token; it is not a Run revision, observation cursor or execution epoch.

The SQLite file uses a closed private physical schema and format identity. An
unknown format is refused without migration or deletion. The trusted Host supplies
a private owned directory; files are created with owner-only permissions and
existing symlinks or nonprivate files are refused. This physical adapter requires
POSIX ownership checks and SQLite STRICT-table support. Those requirements do not
apply to importing or using the Remote Client.

Transactions use SQLite's existing exclusive write serialization and FULL
synchronization. Competing generations cannot replace one another. A failed
commit acknowledgement remains an exception; the adapter neither reports success
nor repeats the write. The Host must read the same original bytes and let Core
decide the next operation. If both commit and rollback fail, the retained connection cannot return its
uncommitted bytes or accept another write. Only its pending cleanup may proceed.
Close releases the connection, preserves persisted records and performs no Run
cancellation or recovery. Failed close retains its
exact cleanup handle, including initialization failures.

Record count, individual byte length and aggregate payload length have explicit
physical ceilings. Oversized retained rows are refused before returning their
payload to Python. These payload limits do not cover the SQLite page cache,
rollback journal, file/schema overhead, Python descriptors, Core Wasm memory or
DuckDB workspace. Their simultaneous holdings still require the existing shared
resource Owner; a byte-store test alone establishes no aggregate Local bound or
successful Run recovery.

### Durable physical capacity

Private byte-store format 2 adds the existing Native SQLite `actql_capacity`
reservation fields alongside `core_bytes`. Format 1 is refused without migration
or deletion; retained evidence and saved records are not relabeled. This is the
Python byte store's closed physical format, not Native publication Store format
interoperability.

The physical connection selects its existing `temp_store = FILE` configuration
before its first catalog or snapshot observation, including on reopen. Later
TEMP configuration changes may discard the schema underneath prepared SQLite
observations; the constructor does not change that configuration after any
such observation has begun. This ordering adds no schema, Owner or authority.

The existing one-time owned-file initializer selects private format 3 when the
same SQLite library supports the existing Run-Definition expression. It adds
only the actual UNIQUE index over the nested Run Definition CID, adapted from
the Native physical index to `core_bytes`. It is not uniqueness by Program or
user-supplied Run name. A distinct Definition remains distinct; SQL NULL or an
index entry is never typed Run admission. Fresh writes still pass the complete
existing Core registration checks before their original transaction.

The raw constructor and existing format-2 files retain their closed legacy
format. A known missing optional `json_extract` function selects that existing
format before any index mutation; other probe errors propagate unchanged and
never select a fallback. Reopen performs no index installation, metadata repair,
backfill or migration. Missing or colliding format-3 catalog entries refuse.

A same-reader catalog observation compares the original application identity,
version, complete bounded main catalog, required expression and absence of TEMP
shadowing. It retains the same physical transaction, thread, original current
callbacks, query-work ceiling and failure latch. Its scalar selects an existing
read algorithm; it is not an Account Allow, custody proof, reusable current token
or a substitute for selected nested-original validation. Unknown observations
refuse rather than imply legacy absence. Private ABI84 adds this physical scalar
import and keeps exact generated Python and compiler-C declarations; older
installed modules are refused through the existing ABI/source binding.

The private `reserve_capacity`, `read_capacity`, `capacity_usage` and
`release_capacity` port preserves the Native physical contract: namespace and
material key remain exact UTF-8 strings, amounts are nonnegative signed 64-bit
integers, identical acquisition returns an existing reservation, and different
amounts collide. SQLite serializes acquisition and checks both byte and object
totals before inserting. Trusted Host configuration supplies the limits. Capacity
metadata has a separate row ceiling equal to the byte store's `max_records`,
including zero-amount reservations; byte-record ceilings remain unchanged.

A lost commit acknowledgement remains unknown. `read_capacity` only reads the
original namespace/key and returns physical amounts; it neither inserts nor
releases. The Host must bind that actual store and observation to the original
Core request's Store authority, material identity and maximum before confirming
the existing Core transition. A read miss does not grant a retry. Releasing
requires the exact original amounts and is called only after the existing Owner
acknowledges physical cleanup. Failed deletion retains the original reservation;
failed transaction rollback leaves the same connection pending and unreadable.
Closing the connection preserves durable capacity and does not cancel a Run.

`compare_exchange_reserved` fences the original byte CAS with the exact retained
capacity row under the same SQLite transaction. Its immutable observation must
name the written material key. The existing batch port can apply the same fence
to its original material and dependent opaque records. A reservation removed or
changed after an earlier read produces a physical conflict with no writes, no
capacity reacquisition and no automatic resend. This follows the Native physical
transaction boundary; it does not interpret Core record states. A lost commit
acknowledgement still requires original read-only observation and Core decision.
The trusted Host must retain the original cleanup responsibility and coordinate
release through the existing Owner; a physical row is not a cleanup permission.

The existing payload Owner's
`prepare_observed_publication_payload_reserved` checks the original nominal
record's Store authority, the existing `publication_payload` namespace, material
identity, exact maximum bytes and one object. It prepares the same existing
`Intent` to `Reserved` transition; the record remains `Intent` until the trusted
Store persists the exact next record and
`commit_observed_publication_payload_transition` confirms its original revision,
request and canonical bytes. A matching capacity observation alone is neither a
durable record commit nor permission to create a file. Foreign capacity facts,
changed amounts, later states and stale transition commits are refused. This
Owner function does not by itself provide a Wasm transport or public Host port.

This port alone does not install a Store, complete filesystem payload custody,
authorize a publisher or acknowledge `Reserved`, `Writing`, `Sealed` or Run
completion. SQLite workspace, Core Wasm memory, transfer buffers, DuckDB workspace
and the durable file reservation remain separate holdings for the existing shared
resource Owner. Physical capacity tests do not establish global memory accounting
or public Local recovery.

## Original Core material transfer

The private `actql_material_*` family projects records from an existing prepared
Run. `reserve` selects checked materials (1), the original request record (2),
the original definition CID (3), or exact authored input bytes (4). It reserves
a 1 MiB output allowance before invoking an encoder. Its physical copy allowance
covers simultaneous Python destination and immutable byte copies. This is a
transfer reservation, not an aggregate Core encoding or execution guarantee.
The existing materials encoder retains its stricter closed-record limits.

`produce` uses existing Owner projections. Its handle is issued before encoding,
retained on interruption, and never implicitly retried after a trap. Repeating
a completed projection reads the same output. Output slots cannot be filled or
sealed as authoring inputs and expose no parsed source-node capability. Their
actual byte length is independent of the reserved upper bound; empty output is
distinct from incomplete output. `actql_buffer_byte` reads these immutable bytes
under the same instance and loan. The original Run cannot close while an output
handle remains live. Output retirement requires the same physical cleanup
acknowledgement as input transfer and retains its capacity on failure.

Python retains an exact output-loan object; copied or foreign objects cannot
retrieve or release its bytes. Allocation of the large destination follows Core
reservation. Reads are bounded to the admitted length and do not store partial
records on invalid lengths, invalid bytes or traps. A physical adapter must
finish consuming the borrowed bytes before acknowledging output cleanup.

`reserve_restoration` retains an immutable input loan before codec admission.
Its closed physical envelope contains `materials` and
`expected_run_definition_cid`, both strings. The trusted Host supplies the
retained original CID; neither field is a caller grant. `restore` invokes the
existing task-Run materials Owner and keeps the exact typed outcome. `restored`
reports private readiness only: 0 is codec admission, -32 a typed rejection,
and -33 no completed outcome. Closing restoration waits for physical stop.

These projections and codec admissions perform no Run acceptance, durable
commit, Source acquisition, task dispatch, publication or recovery start. The
saved exact authored input and request are separate records from lowered Program
materials. The product Host still needs to connect original journal facts,
current authorization, completed retained outputs and publication Owners before
it can resume the original Run. Earlier ABI modules are refused by the ABI 23 bridge;
no compatibility adapter or alternate runtime route is retained.

## Original execution Owner restoration

The captured-Source profile uses
`restore_captured_source_local_run_from_materials` against the same readmitted
task materials Owner. The restored compilation, admission and Run definition
remain one physically bound set. Fresh authored provenance must have identical
checked Program/parameter and environment identities; it cannot substitute its
execution Owner. The exact original request, authority scope, current account,
execution context and policy remain required. Source-free and captured profiles
are selected explicitly from the checked acquisition inventory, not retried as
fallbacks after semantic refusal.

Restoring that plan is distinct from restoring completed Source bytes. The
existing Source capture codec binds the saved descriptor and rows to its exact
requirement CID and original Run binding. Receiving custody owns its own
lifetime: loss or close cannot acquire or revoke the original capture. Neither
codec readmission nor configuration authorizes Source I/O, proves a completed
task or starts replacement work. Durable process recovery must subsequently
re-admit the saved completed Source/Compute and publication facts through their
existing Owners before deciding the next permitted action.

`restore_source_free_local_run` retains the material codec's original checked
Owner, task compilation, admission and definition. It does not issue a new Run
definition or refresh its lifetime. Fresh preparation of the saved authored
input supplies provenance separately; its identity and checking environment
must match the retained execution Owner. An equivalent fresh checked object
cannot replace the exact Owner retained by the compilation. Compute setup and
activation therefore consume `local_run_prepared`, while authored diagnostics
retain the separate original input.

Restoration checks the current subject-bound authorization, original request
relation, authority scope, execution context and Host policy through existing
Owners. The typed-material overload checks physical compilation binding even
when callers assemble the public material fields themselves. Neither overload
changes durable reservation, physical-start, completed-task or publication facts.

The private `actql_run_restore` entry consumes an already readmitted material
handle and a Run handle reserved against the saved request record. It does not
decode and compile the materials a second time. Its installed configuration
supplies the current Account Owner, tuple, context, policy and authority scope.
A handle selects compilation or restoration once; another operation or material
handle cannot replace a completed or interrupted invocation. The material loan
remains live until dependent Run handles close. This is plan restoration only;
original process recovery still requires durable completed-output, start,
publication and cleanup observations from their existing Owners.

## Installed Source publication

The private `actql_program_install_source_environment` takes one
pre-reserved, closed Host configuration with `environment` and `publication`
strings. The original canonical environment is admitted by the existing Check
Environment Owner. `client_source_publication` contains the same publication
interpretation used by the Node Host: generation, Source View, schema, policy,
Source reference and alias checks precede query binding. The Source-backed
profile and source-free profile remain explicit supported configurations;
neither performs Source I/O or grants read authority during installation.

The installed input loan outlives all dependent preparation and Run handles.
Exported original Run materials carry the admitted environment wire, rather
than mistaking its outer Host configuration for an environment. Publication
metadata and authored Program/AQL remain distinct. The scalar Run adapter
selects the existing single-Source or source-free compilation profile from the
checked acquisition inventory; unsupported profiles are refused by those
Owners before physical dispatch. This boundary does not provide durable
acceptance, an acquisition callback or recovery of completed physical work.

## Interrupted physical bridge calls

An exception after entering Wasm puts the private bridge into closing mode.
It retains the instance, original physical tickets and issued loans; fresh
reservation, transfer production, Native start and receipt feed are refused
before further I/O. Explicit retirement of an existing loan remains possible.
This barrier does not assert that a trapped Core retired its resources, refill
instruction fuel, retry the interrupted operation or dispose a pending Run.

## Installed Host root capacity

Module compilation inputs and physical acceptance are distinct evidence.
The maintainer component producer's closed compile-only module original binds
the selected clean source and original compiled source, pinned toolchain,
generated ABI, actual regular module and link input/output identities through
one shared verifier. Equal-input reuse retains its original compiled source;
it does not relabel an old build or imply a complete compiler read trace.
The image compiler may consume that preparation before physical probes, but
must hold the original provider-backed scope through Config, pool, Engine,
module serialization and confirmed cleanup. Preparation is not a capacity,
Runtime, Run or authority admission.

Final component assembly requires the stronger physical receipt for that
exact selected source/module, including the same verified module original and
successful contract, result, physical and workspace observations. Missing
physical cases or a compile-only scope refuse assembly. This order avoids
requiring physical image execution before the image can be prepared while
preserving the final physical gate, original recipe/library/image bindings,
normal funding refusal and image-only installed loader.

The maintainer compiler and final runtime assembly share one pinned binding
source/two-library staging implementation. Compiler preparation takes the
selected source-original recipe directly; it does not synthesize LocalComponents,
an image or physical success to reach that implementation. Final assembly keeps
its stronger component/image/physical admission. Source-only verification does
not require or import an ordinary Wasmtime installation. The compiler imports
only the staged private namespace after acquiring the same staged provider's
original holding. Actual Rust/provider address correspondence precedes Config.
The original preparation files, imported aliases and partial import exceptions
remain attached to compiler custody. A partial import is unconfirmed cleanup;
it cannot release the holding, replace a loaded module, infer DLL unload or retry
with a new provider. This reuse introduces no alternate distribution, runtime
fallback, capacity declaration or normal funding profile.


The installed Host requires explicit trusted Host resource limits when opening the
instance. The existing Ledger reserves the fixed 16 MiB linear-memory allowance
and the configured transfer pool. Physical workspace loans reserve against
that exact Ledger; concurrent workspace and transfer allowances cannot each
spend the same remaining capacity. The scalar configuration is range-checked
before optional engine import and admitted again by the existing Core Ledger.
The instruction fuel policy is independent and unchanged.

`actql_workspace_reserve` registers a pre-I/O workspace loan and
`actql_workspace_close` retires that same loan after separate physical-stop
and cleanup callbacks. A workspace ticket cannot also select a transfer or
command output. Python keeps the issued identity-bearing loan; copied, foreign
and cross-family loans fail before I/O. Rejected reservation removes the
unissued Python registration, while a trap retains it and closes admission.

`actql_buffer_reserved` reports that pool's live lease; the new
`actql_workspace_root_reserved` reports all live execution-resource reservations
on the shared root. Pool close releases only the pool and waits for workspace
retirement before acknowledging Host retirement. The fixed Wasm lease is marked
cleanup pending and remains reserved while the Store is still alive. Physical
Store/Linker/Module/Engine disposal belongs to the same Python bridge and keeps
failed handles for retry. No logical operation reports that live Wasm memory
has already been returned.

Bootstrap loads the bounded installed module before its own in-module Ledger
can run; it starts no Run or Source I/O. This connection does not yet establish
full product accounting for Wasmtime compilation/code memory, Python metadata,
parsed command values, SQLite cache or DuckDB workspace. The installed assembly
must bind the remaining physical limits and reservations before advertising an
aggregate runtime guarantee.

## Physical DuckDB workspace assembly

The private `DuckDBWorkspace` obtains an existing Core workspace loan before
entering database configuration/open/connect. Root-capacity rejection therefore
starts no native database operation. Its callbacks bind the same connection
and original loan; failed native construction keeps its original cleanup handle
and Root reservation rather than opening another database.

Stop observation first seals new connection I/O and then inspects the original
I/O lock. Busy physical work remains pending; coroutine cancellation does not
substitute for that observation. Statement and read-view handles must still
complete cleanup before the connection can close and release its reservation.
The assembly neither requests interruption nor changes a Run's terminal state.

The trusted Host must obtain Source/Run authorization from existing Core Owners
before calling this physical assembly. Its configured workspace envelope and
DuckDB buffer-manager memory limit are distinct. This connection does not claim
that the buffer-manager setting limits every DuckDB allocation, or that all
Python/native runtime memory is already covered by the product Root budget.

## Exact Native capture into Compute

Private ABI 8 adds `actql_compute_reserve/configure/configured/close`. Reservation
borrows the immutable configuration before evaluation and is issued only once
for the exact completed Native attempt. It does not activate a task. The closed
configuration carries current `read_account`, `registry`, `values`, optional
`fragment` and optional `ordered` bodies; explicit NULL is not an omitted body.

Configuration rechecks the existing read Account Owner, asks the Native Owner
for the exact bounded buffered capture, and configures existing captured Compute on the
same root Ledger. It binds the original accepted `LocalRunPhysicalStart`; no
fresh physically-unstarted assertion or replacement Run start is manufactured.
The Host reference is retained before start binding. Interrupted construction
keeps its pending record, input borrow and Native parent rather than declaring
cleanup safe or silently invoking construction again.

Native attempt closure waits for its Compute children. Compute retirement stops
new work, closes each existing result port and refreshes the existing task
Owner. `captured_task_retirement_pending` observes tracked task/result records
and pins, independent of other root workspace reservations. It excludes
caller-owned Source captures and resident-environment responsibilities, which
remain with their existing Owners. The sealed Local profile preserves those
boundaries. Configuration/readiness is not dispatch, publication or success.

## Managed task custody

Private ABI 9 adds opaque task reservation, activation, bounded input feeding,
execution, finalization and retirement. Reservation selects the next task from
the existing captured strategy; Python cannot supply a task identity, rows or a
completion assertion. Activation rechecks the current Account and binds the
original accepted Compute start through `start_local_compute_task`.

Input feeding copies only the original Native capture or an exact completed
producer from the same Compute Host. Each call advances within its explicit
positive quantum. Completion requires the existing driver's distinct execution
and finalization progress, settlement and completed-output decision. Progress is
cleared between execution and finalization, so execution completion cannot be
reused as finalization evidence. These facts do not establish public Run success
or Named Result publication.

A task retains its Compute and current-configuration parents until existing
physical-stop and cleanup observations allow retirement. A producer cannot
retire while another retained task refers to its output. Failure or an
interrupted invocation keeps the original handle; the bridge neither replaces
the invocation nor manufactures completion. Result publication, durable
recovery and the ordinary Client facade remain separate connections.

## Checked Result export custody

Private ABI 10 adds Result preparation and bounded physical chunk loans. A
reservation selects the checked Named Result occurrence from the same captured
Compute graph and accepts only its exact live completed task. Python cannot
replace the producer with a schema-equivalent output. The existing managed
publication bridge re-admits original retained rows, and the existing captured
Result transformation Owner holds the Result pin through preparation and its
transfer to the export. Input feeding and transformation advance with explicit
positive quanta.

The private profile limits each payload batch to 65,536 bytes, total export
wire to 1,000,000 bytes and rows to 100,000. Existing value, schema, mapping,
ordering and workspace limits remain separate enforced obligations. These
ceilings do not override a checked Program or its root capacity. They are not
a guarantee that every Python, Wasmtime or native allocation is already covered
by the product memory budget.

Each chunk obtains its existing buffer reservation before advancing the export
or allocating a Python destination. Only one issued chunk can remain live per
export. Repeating production of a known chunk reads its retained decision;
neither an acknowledgement loss nor another Python copy advances the exporter.
Capacity refusal still returns cleanup custody. A pending close seals the chunk
against production and retains that original handle for cleanup retry. Physical
ticket uniqueness applies across inputs, workspaces, Native commands, materials
and Result chunks, including refused output reservations.

The final marker comes only from the export Owner's successful finish. It is
neither durable publication nor Run success. Closing an export waits for its
physical chunks and releases only its existing Result pin/bridge; closing its
parent task waits for retained exports. Public read authorization, durable
publication/replay, original Run admission and the ordinary Python Client
connection remain additional boundaries. This ABI grants no public Result
access and performs no Run cancellation or automatic execution/replay.

Private ABI 11 adds a scalar projection of the retained Native configuration
issue for trusted physical Host diagnosis. It preserves the original typed
failure and distinguishes setup boundaries without interpreting messages or
dispatching a replacement attempt. These private categories are not public
Source reasons; caller disclosure and public diagnostic contracts remain
separate gates.

The current receipt ABI selects the existing non-streaming Native receiver.
Before constructing that receiver, Core reserves its declared buffered retention
and materialization capacity on the same Root Ledger. Compute captures that
receiver through `capture_native_host_source` with the buffered profile; it does
not request a retained stream material that was never staged. The reservation
outlives every Compute and Result consumer and is settled only after physical
stop, Native closure and physical cleanup. A failed cleanup keeps the original
attempt handle and its reservation. Root pool closure refuses remaining Native
and downstream custody instead of clearing those records. This is a declared
bounded envelope, not a claim about total Python/JIT/allocator RSS.

Private ABI 12 exposes the original retained task issue category to the trusted
physical Host. It does not infer failure from an error message or expose Source
metadata to a caller.

Private ABI 13 reads an existing strategy assessment and its exact Root capacity
and reservation quantities. It does not rerun search, derive admission from
explanation text, or change a Run. The trusted Host may inspect the reported
resource rejection before fixing its preflight inventory. A single assessment
is not a claim that all strategies were explored.


Private ABI 14 exposes the existing single-capture Local capacity inventory
through `actql_source_capacity`: retained, execution ceiling and transfer bytes.
The checked requirement must match the installed Native configuration; the same
Compute sequence/store inventory sizes the retained suffix. Native retained
capacity is additional to that suffix, under the existing 512 MiB inventory
ceiling. This query starts no physical I/O and grants no reservation, Source
permission or execution guarantee. Root admission still checks overlapping
Wasm, transfer, DuckDB, Native and Compute reservations. Earlier modules are
rejected rather than adapted.

## Durable dispatch reservation boundary

Private ABI 15 projects `actql_run_dispatch_action` from the existing common
Run-start Owner. The trusted Host supplies the exact retained request record,
Run Definition CID and closed physical journal facts. Current installed Account
authorization and the original context/tuple are checked in Core. The result
is either ReserveDispatch or ReconcileReservedDispatch; malformed records,
foreign handles, changed intent, Run identity and authority are rejected.

The physical Python adapter performs one compare-and-exchange after that
decision. A competing generation or lost commit acknowledgement is unknown;
there is no automatic retry. Reconciliation reads the original record and
evaluates current Core authority again. Physical CAS generation is distinct
from the Run/control revision. A dispatch reservation is neither Submission
admission nor a physical-start claim, and cannot authorize Source or Compute.
The separate existing physical-start Owner and atomic start claim remain
mandatory before physical I/O. No missing record supplies evidence about
previous execution. Closing the byte store cancels no Run.

The journal adapter stores physical flags with the original Core-issued request
kept as an exact string. It does not normalize or reissue the request. Original
materials, public Submission/epoch binding, durable Result publication and
whole-product resource accounting are separate required product connections.

### Submission epoch and identity projection

Private ABI 16 adds `actql_submission_reserve`, `produce`, `length`, and
`close`. The trusted Local Host installs its current account/access tuple and
authority scope before reserving an epoch or reference projection. Core checks
that tuple through the existing Account Owner, binds the exact authority scope,
and delegates epoch encoding, CID, caller identity and half-open validity to
the existing Submission Owner. This projection never admits a Run or starts
Source, Compute, Model or Effect. Expired references retain their identity for
original-operation lookup; that does not authorize a new admission.

The output has a 4 KiB bound reserved before encoding and retains its exact
input loan and configuration. A producer interruption cannot re-evaluate the
same invocation. Output cleanup and input-reader stop are separate facts:
failed close preserves the same handle and configuration pin, and a successful
output cleanup is not repeated while input stop remains pending. Earlier
private ABI modules are refused; the public Client–Host contract is unchanged.

The Python physical adapter authenticates the exact Core-issued epoch wire with
HMAC-SHA-256 and persists its key and monotonic clock in the existing opaque-byte
store. Bootstrap consumes an exclusive, empty new-file observation once.
Missing material after reopen or a failed bootstrap does not create a new key.
Each clock advance uses one physical CAS; conflict or lost acknowledgement is
unknown and does not cause an automatic retry. The physical generation is not
a Run revision. Current account/scope evaluation remains mandatory on each Core
projection; an old authenticator is not a permanent authorization grant.

### Captured Source publication facts

Private ABI 19 borrows the original Native capture from its configured Compute
Host. Source identity uses the existing bounded Relation identity frame. Each
advance retains its cursor, limits, cancellation and monotone logical work; it
neither reacquires the Source nor releases the acquisition reservation. The
retained-wire representation continues to use its own existing identity path.

The portable Local wrapper issues logical input and Source evidence using the
existing checked graph, exact capture, Catalog membership and Source issuers.
It checks current read authority before preparation and again after the final
yield. Authority scope and effective policy come from the original Run and
checked Source facts, not authored input or arbitrary caller CIDs.

A Source projection reserves its complete 64 KiB output and physical-copy
allowance before encoding. It pins the original Compute/acquisition until
explicit close succeeds. Failed output cleanup or input stop retains the same
child handle; successful output cleanup is not repeated. These typed facts
are inputs to the existing invocation/publication chain, not Run admission,
terminal success, durable Result publication or recovery permission.

### Original Local normalization and captured invocation

Private ABI 19 retains material kind 5 for the original completion-free Local
normalization journal. It issues the journal through the original checked
preparation and compiled Run Plan owners. A real semantic completion, an
uninstalled profile or exhausted audit is refused; successful compilation is
not a substitute for the completion inventory. The original nominal projection
remains with that Run handle, and the output uses the existing reserved buffer
and retryable cleanup custody. It does not grant execution or durable recovery.

Source publication requests include `capture_started_at` and
`capture_completed_at`, supplied by the physical Host for its original capture,
in addition to `observed_at` and the bounded identity-scan limits. The closed
output contains exact `logical`, `evidence`, `observation` and `invocation` wire
strings issued by the existing publication owners. Issuance rechecks current
Run and Source authorization against the exact original Compute and capture;
it neither reacquires Source nor starts another task. These records remain
intermediate publication materials, not a terminal Run or durable publication.

### Bounded final Result publication capture

Private ABI 19 reserves one complete output before projecting the exact live
Source invocation and completed Result exports. The closed trusted Host request
contains `results` (original export handles), `retention` (admitted policy wire),
`max_work` and `max_workspace_slots`. Duplicate, foreign, unfinished or closing
parents are refused. The full declared Result inventory is validated by the
existing Manifest Owner; a selected subset is not a complete publication.

Each Result snapshot advances through the existing bounded output/snapshot
Owner. The original normalization journal and Source evidence bind the single
Receipt. Captured Run assembly uses the original prepared Program's distinct
authoring-context sidecar and an empty Model inventory for this Effect-free
profile. Grammar-owned metadata is extracted without collecting business
values named `meta`. The final Manifest, Receipt, snapshots and authoring
sidecar feed the existing bounded Captured Run Owner. Every advance and final export
rechecks live original pins and current Run/Source authority; no Source or task
is executed by this projection. The closed output contains `manifest`,
`receipt` and `captured_run` wire strings. It does not commit durable storage,
produce a public Run state, or refresh the original provenance.

`max_work` bounds the reported snapshot/capture cursor work. It does not claim
that synchronous contract projections or the full product fit the default
fuel envelope; those remain separate verification boundaries.

The child retains its Source and Result parents through cancellation and failed
physical output cleanup. Parent close seals further production but cannot
release those pins until the same child finishes cleanup. Closing the child
cancels its snapshot/capture preparations without cancelling the original Run,
then retires its output and input loan through their existing cleanup Owners.


### Original Result storage binding

The portable completed-export Owner can issue a durable representation binding
for its original live receipt, Result definition, ordering evidence and artifact.
It derives the row count, field order, schema and existing canonical row-wire
codec pin from that export. The physical Host supplies the observed byte count,
SHA256, material generation and Store authority identities. A different size or
digest is refused before the existing durable-binding issuer is called. This
entry describes the original canonical export bytes, not another physical codec.

The Local wrapper obtains the Run definition, invocation and retention from the
original nominal LocalResultPublication and rechecks current Run/Source authority.
No adapter-generated semantic JSON or replacement provenance is accepted there.
Cancelling a borrowed snapshot leaves its parent export facts live; releasing the
parent revokes binding issuance. Issuance alone proves neither physical retention,
Store commit, publication permission nor a Run outcome. A durable Store must
still verify its actual payload and current publication authority separately.

### Original checked publication intent and preflight

`prepare_local_publication_intent` reads every Named Result name and producer
from the original LocalRunPlan's checked graph. The existing checked inventory
Owner creates their Result definitions, and the existing publication issuers
create the request and attempt. No supplied subset, semantic JSON or replacement
Result definition enters this path. A Host-selected inventory limit rejects the
whole preparation when exceeded; it never shortens the inventory. Result names
retain the existing Result Definition Owner's canonical-text requirements.
The Host supplies the original fence CID and optional external idempotency key
to the existing attempt issuer. This fixes intent; it does not prove a live fence
or turn an idempotency key into permission to repeat an unknown operation.

`check_local_source_publication_preflight` requires the exact captured Source
invocation and its original plan. It checks current Run and Source access and
live Source identity, then delegates the complete immutable scope to the existing
publication preflight. Preparation must precede the first Compute activation;
an active or completed Compute frontier or a pending activation grant is
refused. The Host must retain this preparation before invoking its existing
task activation Owner.

The resulting opaque LocalPublicationPreflight retains the original intent,
invocation and a copy of the aligned retention array. Mutable policy arrays are
not exposed. `issue_local_preflight_result_publication` checks the exact Result
definition and derives its retention from that preparation, then calls the
existing completed-output and Local Result publication Owners. It rechecks
current access and live Source custody, so an old preparation is not permanent
authority. Preparation performs no Source acquisition or Compute activation.

These facts grant neither Run admission nor Store publication permission. The
physical publisher must separately check its current publication authority and
durable transaction boundary. The preparation's original admission, compiled
plan, Program definition, Source logical input, policy and authority references
must remain bound through final Receipt, Captured Run and commit validation.

### Private preflight custody before activation

Private ABI 22 adds `actql_publication_preflight_reserve`,
`actql_publication_preflight_prepare`, `actql_publication_preflight_length` and
`actql_publication_preflight_close`. The original completed Source publication
and a sealed intent input are retained by one nominal child. The input is a
closed object of Host namespace, policy/target CIDs, request/attempt timestamps,
fence, optional external idempotency key and the complete aligned retention
array. Neither semantic Result definitions nor a replacement Run or invocation
are supplied. The existing checked intent and preflight Owners validate it and
return the original request/attempt bytes. NULL does not mean absent.

`actql_task_start` requires this retained preflight and checks current Run/Source
access before calling the existing activation Owner. It does not derive a task
grant from preflight success. Cached start and preflight reuse also check current
access. The child remains attached to its original Compute and Source; it cannot
be replaced while live. Parent close seals further use while retaining custody.

Publication accepts only the complete original Result occurrence list and work
limits. A late `retention` field is refused; policies come from the retained
preflight. The existing nominal cache/reuse guard retains original Receipt and
artifact identity after a cancelled snapshot, and each Result must match its
checked inventory index. Commit request, attempt and index are derived from that original intent by
the existing issuers before the existing commit Owner is invoked.

Close retains the child while tasks or publication children exist. Output
cleanup and the exact input-borrow stop/return must both succeed before removing
the handle. A failed cleanup can be retried on that same handle; closing a loan
neither certifies Run cancellation nor changes the durable outcome. Python
preserves the same nominal family, refuses copies before I/O, and returns exact
Core bytes without reconstructing intent. Its loader checks the four scalar
signatures together with the current private ABI and accepts no older fallback.

This preflight does not establish a live physical publication fence, current
publisher permission, Store installation or durable Run recovery. Those remain
separate obligations through the original final Receipt and commit chain.

### Original publication commit validation

Private ABI 20 adds `actql_publication_prepare_commit`,
`actql_publication_advance_commit`, `actql_publication_commit_progress` and
`actql_publication_finish_commit` on the original publication handle. Preparation
now borrows a closed input containing only `bindings` and `committed_at`.
Bindings are an array of admitted durable binding contract strings. Private
ABI 23 derives the request, attempt and candidate index from the original
retained preflight using the existing index issuer. Supplied replacements for
these contracts are refused as unknown fields; Python does not build their CIDs.
The Receipt, Captured Run, Manifest, original normalization and Result inventory
come from the retained Core handle rather than supplied replacements.
The physical Host supplies binding facts; consistency validation does not prove
that physical payload bytes were written.

The existing bounded publication commit Owner checks the complete chain. Capture
and commit validation share the original `max_work` budget and workspace limit.
Every advancing or finishing call checks current Run and Source authority. Once
preparation starts, a different input cannot restart that handle's validation;
traps and cleanup failures retain the same input and original parent custody.
Closing cancels the existing Owner and returns its borrowed input only after the
physical stop callback succeeds. Earlier ABI modules are rejected, with no
compatibility fallback.

Successful finish proves chain validation only. The physical Store must separately
verify actual payload facts, current publication authority and the durable commit
boundary. This ABI does not write an index, acknowledge persistence, admit a Run,
retry an unknown operation or supply saved-Run recovery.

### Validated commit candidate export

The portable publisher callback port is installed by the trusted Host using the
original preflight request and attempt and a fixed Store authority identity.
It presents the same six facts as Native publication: stage, namespace,
authority scope, Run, request and optional index. Policy and target are the
external references in the original request preimage; projection does not
publish their bodies or supply their current authorization. The Host must
select their genuine configured originals and evaluate its independent
publisher authority for `request`, `commit` and `return_committed`.

Every check fences the original nominal request/attempt and Store identity,
then checks current Host custody before and after the authority callback. The
Local adapter also obtains a fresh account for current original Run/Source
authorization on both sides. Neither Run/Source access nor an SDK boolean
implements publisher authority. A denied or revoked check changes no Result,
payload, attempt or Run state. A prior successful callback caches no grant.
Returning an existing committed index can refer to an earlier attempt of the
same request; its stored full chain still requires the existing validator.
This callback port does not install a Store, validate physical payloads, commit
an index or establish public Local admission or durable recovery.

The portable `prepare_local_preflight_payload_request` projection binds one
original nominal Result to the publication attempt fixed before Compute. It
rechecks original preflight, retention and current Run/Source access, then asks
the completed-output Owner to project the existing `PublicationPayloadRequest`.
That Owner requires a live EOF receipt, issued evidence and artifact, and obtains
schema, codec, ordering, byte count and row count from the exact retained export.
Only physical Store authority, material generation and a payload byte ceiling
are supplied by trusted Host configuration. The ceiling must cover the exact
payload; it does not replace aggregate workspace or transfer reservations.

This request does not start I/O, authorize a publisher or create a durable
record. The existing publication payload Owner retains responsibility for
reservation, writing, sealing, durable transition confirmation and cleanup.
Retained metadata or cancellation of a borrowed snapshot cannot replace the
original live receipt, and a released parent cannot issue another payload intent.

Private ABI 23 adds `actql_publication_commit_export_reserve`,
`actql_publication_commit_export_produce`,
`actql_publication_commit_export_length` and
`actql_publication_commit_export_close`. Reservation requires successful finish
of the original complete-chain validator. Encoding returns exactly the existing
Core's `request`, `attempt` and `index_entry` contract strings, within a reserved
1 MiB output buffer and separately reserved physical copy allowance. Current
Run and Source access is checked before initial and cached production.

The child pins its original publication. Parent close seals new production and
retains custody; failed output cleanup retains the same child and reservation
for explicit retry. The parent still owns its original immutable commit input
borrow and nominal Result/Receipt/artifact. No source acquisition, task
activation, Receipt reissuance or physical Store call occurs during export.

The index is a candidate accepted by the semantic validator. Its `committed_at`
is a supplied physical observation, not proof that a Store transaction committed.
The physical Host must separately check current publisher authority, verify
payloads and obtain durable acceptance. A copied export never supplies those
permissions. Python returns the exact bytes and treats closing this loan as
resource cleanup, without cancelling a Run or resending a publication.

### Original Result storage binding output

Private ABI 21 adds `actql_result_binding_reserve`,
`actql_result_binding_produce`, `actql_result_binding_length` and
`actql_result_binding_close`. The strict Python loader requires their exact
signatures and ABI version; earlier modules are rejected without a fallback.
Reservation selects one Result index from the original completed publication
handle and borrows an original sealed input. That input is a closed object of
`material_generation_cid`, `store_authority_cid`, `byte_count` and
`physical_sha256`. Missing, NULL and additional fields are refused. The Host
supplies physical observations; the existing Local publication wrapper derives
all semantic fields from the original Result and checks the observed bytes.

Producing, including reuse of an already produced output, rechecks current Run
and Source authority. A separate 65,536-byte output reservation carries the
unchanged canonical binding bytes. Python tracks only physical loans and does
not reconstruct semantic contracts. Copied or foreign Python handles are
refused before I/O. Once generation has begun, invalid observations cannot be
replaced on that handle.

The child retains its original publication until output cleanup and return of
the exact input borrow both succeed. Parent close seals new production but
retains parent custody while a child exists. A failed physical stop or cleanup
keeps the same child and reservation available for cleanup retry. No Source or
Compute replay is part of this operation. Binding output proves neither Store
commit nor durable publication, admission, recovery or a Run outcome. The
physical Store must still verify its payload and current publication authority.


Private ABI 24 adds `actql_publication_preflight_retire_output`. After the Host
has copied the original request/attempt projection, this operation retires only
that output allocation through the existing buffer Owner. Pending physical
cleanup returns `-9` and retains the same output reservation and handle. Only
successful cleanup marks the output closed. Repeating successful retirement
performs no second physical cleanup. Output reads then refuse; the Python bridge
has also discarded its transport bytes through the original cleanup callback.

The original semantic preflight, admitted request/attempt, Source pin and exact
input borrow stay live. Task activation and later original commit preparation
still use that nominal preflight and recheck current authority. Output retirement
is neither preflight close nor publisher permission. Full preflight close keeps
its existing child guards and returns the original input borrow only after its
stop/cleanup responsibilities complete. Failed earlier Source/input close cannot
release their held capacity. No capacity formula, resource ceiling or fuel budget
changes, and no Source or Compute is repeated to recover space.

The private ABI26 `actql_publication_retire_output` releases only the completed
publication wire projection through the existing buffer Owner. A successful
retirement preserves original Receipt/Captured Run roots, Result pins, preflight
and exact input borrow for child binding and commit validation. Cleanup failure
retains the same output handle and allocation; only successful cleanup marks the
transport closed. Retirement grants neither publisher authority nor Store
acceptance. Full close still waits for children and returns the original borrow.
The private Python method discards its copied wire only after the same physical
cleanup succeeds, while retaining its nominal semantic loan.


Private ABI27 keeps a child replay under the original typed payload request,
preflight and completed Result. Core's existing completed-output replay Owner
provides bounded chunks and proves its final digest. Each production and cached
read rechecks the original current Run/Source/custody boundary. One reserved
chunk pins its request until exact cleanup succeeds; lost acknowledgements use
the same chunk rather than consuming more bytes. Request close cancels only its
child replay, retains live chunks and retries the same original input borrow.
Python exposes exact bytes and the Core EOF marker. It does not infer durable
payload sealing, Store installation, publisher authority or Run completion.

The existing payload Owner can confirm a prepared transition from an admitted
durable record using `commit_observed_publication_payload_transition`. It checks
the original Store authority, material identity, expected successor revision,
original request identity and exact canonical successor bytes before invoking
the existing transition commit. Format admission alone proves no physical
persistence: the trusted Host adapter must supply a real observation from that
same Store and key. Python's private `LocalByteStore.read_exchange` reads the
exact successor of an original physical CAS without repeating the write. Equal
bytes at a later physical generation do not confirm the old CAS. Missing or
mismatching observations remain unresolved, and neither API grants publisher
authority or changes the Run. The portable Wasm persistence connection and
filesystem payload installation are separate integration obligations.

Private ABI28 projects the existing payload Owner's original initial Intent
record under its nominal request. Production and cached reads recheck current
Run/Source authorization. The physical Host marks a single CAS attempt before
writing; repeated begin is refused. An uncertain write pins the same record,
parent request and original input, including after a close request. Confirmation
requires an actual observation from the original Store authority, material key,
physical revision zero and exact canonical initial bytes. It leaves the Core
record at Intent: no payload capacity reservation, Writing/Sealed transition,
Store installation, publisher authority or Run completion is inferred. Pending
close can be retried on that same record after confirmation; transport cleanup
failure retains the original allocation. This private boundary still requires
the portable durable-capacity, filesystem and recovery integrations before it
can form the product Local persistence path.


Private ABI29 retains a child Reserved transition under that same confirmed
initial Intent. Its five-field closed input carries actual trusted Host capacity
observations: `store_authority_cid`, `material_generation_cid`,
`capacity_namespace`, `reserved_bytes`, and `reserved_objects`. The original
payload Owner checks the original Store/material, fixed `publication_payload`
namespace, original bounded max_bytes and one object. Preparing or reading the
transition does not advance the original record or reserve physical capacity.
Cached reads still recheck current original Run/Source authorization.

The Host marks one original physical CAS attempt and uses the existing
capacity-fenced byte transaction. Confirmation accepts the same closed physical
record observation as ABI28, but requires the original exact successor revision
and canonical Reserved bytes through the existing transition commit Owner.
An uncertain CAS retains its child, parent record and original Source/input
custody even while closing. Current authorization is required to resolve it.
Transport cleanup failure retains the same allocation; successful child close
releases transport only and never deletes the durable capacity row. The Host's
original Store cleanup responsibility continues independently. Repeated begin
is not permission to resend, and no publisher authority, filesystem ownership,
payload sealing, Store installation or Run completion follows from this bridge.

If the original Core commit completed but its reply was lost, the existing
payload Owner can confirm that same nominal transition read-only. Both the real
durable successor and the current original record must match every canonical
field at that exact successor revision. This performs no second commit or CAS;
later revisions and partial or changed records stay unresolved. It does not
change the existing transition commit's refusal of a stale second commit.

The private Python file port performs physical operations below an installed
private root locked exclusively like the existing Native Store. Original
Core-selected names are single ASCII components; the port never derives names
from Program input or normalizes payload bytes. An exclusive file descriptor is
registered before fallible identity/directory-sync observations. Acquisition
failure exposes that same handle, and directory durability is retried without
repeating creation. Only that descriptor can supply its device/inode facts.

Writes are bounded by the original file byte ceiling and the Host's selected
chunk ceiling. One call performs one physical write and returns the actual short
write count. An uncertain write retains the same handle, refuses subsequent
writes and cannot supply a seal fact. Read-only descriptor size is not a retry
permit. The existing Core Store Owner must decide reconciliation and sealing.
Host-provided capacity and workspace reservations remain separate obligations.

Root close refuses live descriptors. Failed descriptor close retains the same
handle; a lost reply is resolved by actual original descriptor observation,
without closing a recycled foreign descriptor. Descriptor retirement neither
unlinks files nor releases durable capacity, cancels a Run or grants publisher
authority. Filesystem reclaim, final-name installation, persistent original
ownership and public Local assembly remain separate Owner integrations.

After an uncertain close, matching device/inode alone cannot prove that the
numeric descriptor still denotes the same open-file description. A recycled
descriptor can reopen the same inode. The port therefore retries only physical
observation: an equal live descriptor remains unknown, without another close.
EBADF or a different current identity proves the original descriptor retired;
that fact still says nothing about file reclaim, durable capacity or a Run.
If the original descriptor cannot be distinguished, the Host retains pending
responsibility until an authoritative physical stop boundary resolves it.

The same private file port can stop append, flush the original descriptor and
observe its physical SHA-256 with a bounded cursor. `begin_snapshot` permanently
stops new append before flushing. A failed flush retains that same stopped
descriptor; retrying the flush does not repeat a write. Unknown writes cannot
begin a snapshot. `advance_snapshot` reads at most one selected chunk with
`pread`, leaving the original write offset unchanged. The caller can yield or
stop the descriptor between steps. The Host must reserve the hash state and
transient read chunk before using this port; this is not aggregate accounting.

Each step and cached-result reuse checks the original nominal handle, exact
name/device/inode/size and observed modification/change timestamps. A changed
generation, short read or closing descriptor invalidates the cursor; copied
cursors and retired handles are refused before I/O. An ordinary failed read can
retry that same offset without restarting hashing or writing. Empty files yield
the SHA-256 of zero bytes without a data read. The returned identity, size and
digest are physical observations only. The original Core payload Owner still
requires its persisted ownership, current authorization, exact durable
successor and Sealed transition. No pathname adoption, final-name installation,
Store commit, capacity release or Run completion occurs in this operation.

Private ABI32 extends the original `actql_payload_writing_*` transition loan
with kind 3 for Sealed preparation. It requires the original confirmed, owned
Writing record. A closed physical observation carries the original Store and
material CIDs, canonical decimal strings for `device`, `inode` and nonnegative
signed-64-bit `size`, and `physical_digest`. Missing, NULL, extra fields and
noncanonical integers are refused. The existing payload Owner determines exact
ownership, byte bounds and digest validity; the bridge adds no sealing rules.

Preparation leaves the record in Writing. The same loan/current-authorization
guards and original capacity-fenced CAS confirmation are shared with Writing
and ownership. An uncertain CAS retains that original loan, record and input
custody; read-only exact successor confirmation performs no second write.
Neither a physical digest nor a produced Sealed candidate grants publisher
authority, installs a final pathname, commits a Store or determines a Run
outcome. Actual physical installation and durable publication remain separate
existing Owner responsibilities.

Private ABI33 projects original Core-selected staging/object names through a
separately reserved 1KiB `actql_payload_names_*` output child. Only a confirmed
filesystem-owned Writing or Sealed record can create it. The projection carries
the original request CID, Store/material identity and captured record revision.
It uses the existing payload Owner's name getters; Python does not reconstruct
names from a submitted Program or interpret a durable-record compatibility
format. The existing durable record, public schema and identity preimages are
unchanged. These names do not authorize file operations or publication.

Production and cached reads require the same original revision and current
Run/Source authorization. A later transition invalidates that old projection.
The child pins its original record and exact Source/input custody until its
existing buffer cleanup succeeds. Parent close seals further production and
waits for that same child; failed cleanup retains its reservation and handle.
Python checks nominal loans and bounds before copying, returns exact bytes and
does not start an execution, write files or release persistent capacity.

The private physical staging port retains a nominal name cursor before an
exclusive link. Original durable file ownership and the name projection from
that same Core record are prerequisites enforced by the trusted Host assembly;
this port does not manufacture them. Source and target roots must share their
original capacity and lock family. The cursor blocks append and snapshot work
until the known original descriptor moves, and pins both roots during failure.

A known acquired target is checked against the original device, inode and byte
count and directory-flushed before dropping only the exact original name.
Directory-sync failure retries the same link custody without acquisition. An
uncertain unlink observes original-name absence or rechecks the original owned
generation before cleanup; it never unlinks a replacement. An uncertain link
acquisition remains unknown even if the destination currently names the same
inode. Neither another link attempt nor pathname equality supplies its missing
acquisition fact.

Cursor retirement is transport retirement. Pending known/unknown acquisition
first requires actual original descriptor stop; close failure retains the same
handle and both root pins. Retirement does not remove remaining aliases, return
Store capacity, settle unknown acquisition, advance a Core record or authorize
publishing. The existing Store Owner retains the persisted original file and
allocation custody and reservations for reconciliation/reclaim after process
exit. The Host must reserve the fixed cursor and OS workspace before this port.
This connects staging only: physical final-name sealing, durable publication and
normal Python Local assembly remain separate integrations.

The private final-name port requires the completed nominal bounded snapshot of
the original file and the object name selected by its same original Core record.
It flushes and rechecks the staged bytes, then physically stops the original
writer before any exclusive final link. Close uncertainty uses the existing
original-descriptor observation rule: EBADF or a different recycled identity
proves original stop, whereas an equal live inode remains unknown and cannot
trigger another close or link. The same stop rule is shared with transport close.

The final-name cursor retains the file slot and root while stopped I/O remains
pending. A known linked final is generation-checked and directory-flushed before
removing only the owned staging name. Link uncertainty never becomes ownership
from pathname equality or a second link call. Unlink and directory-sync failures
retain the same cursor; only original owned-name cleanup/observation can continue.
Original byte generation/mtime must survive owned metadata operations, and cached
final reuse checks the complete final timestamp/identity stamp. No new payload
bytes are written or acquired while final work is pending.

A successful physical result carries the original snapshot's device, inode, byte
count and digest; it is not a Core Sealed/Commit witness. The existing payload
Owner still needs the original typed preparation and exact durable successor,
and Store publication needs its separate current authority/Policy/target checks.
Cursor retirement requires actual original writer stop and releases only cursor
transport. It never removes remaining aliases, resolves unknown acquisition,
returns durable Store capacity or finalizes a Run. Host reservation of the fixed
cursor/OS workspace and whole-process resource accounting remain separate duties.

The private final-file reader pins the original nominal completed final-name
cursor and opens only its same identity/generation without following links. The
trusted Host first confirms the original Core Sealed record, current context and
separately reserved descriptor/hash/chunk workspace. Python neither reconstructs
publication authority from a pathname nor treats a physical digest as a Core
payload-value proof. Reader descriptors, original file handles and allocation
areas share the existing root descriptor limit, including parallel readers.

Each read returns at most one configured bounded chunk. That exact chunk stays
retained and its offset stays unchanged while the original Core input borrow or
buffer cleanup remains pending. Returning the same chunk rechecks descriptor and
name generation without another read; copied chunks cannot release its custody.
The Host releases a chunk only after its same Core borrow and buffer have actually
retired. No whole-file input is retained by this reader. Current Core authority
must still be evaluated at the consumer boundary before transferring bytes.

Physical finish requires released EOF, original generation and the original
physical digest, then actual descriptor stop. Uncertain close keeps the same
handle, outstanding chunk and root/file pins; only original-descriptor stop
observation can finish transport retirement. An early transport close cannot
become a physical finish. Read/short-read/generation errors do not advance the
offset or become payload verification, Store installation or Run completion.
All named bytes and durable Store capacity remain with their existing Owners.
The Core payload verifier, current publisher and public Local/recovery assembly
remain separate integrations; descriptor/chunk limits are not aggregate process
memory accounting.

Original filesystem Sealed binding uses the existing completed Result Owner.
The record's request body and identity must match the payload intent issued from
that same live export, and its exact physical byte count and digest then pass
through `issue_durable_binding`. This retains the original value, schema,
ordering, codec and retention checks rather than adding a Python payload parser
or another value verifier. A merely prepared Sealed candidate, Opaque custody,
foreign request or changed physical content cannot acquire this binding.

The Local wrapper first reuses the original nominal preflight/Result and
revalidates current Run/Source authority, then checks the original publication
attempt. This is a read-only binding operation: it does not advance the record,
read or rewrite a payload, acknowledge a Store commit or grant publisher
permission. Physical generation opening/digest observation and trusted Host
Store/Policy/target authorization remain separate prerequisites. Parent Result
cleanup revokes the content facts even when a valid durable record remains.

## Original Sealed Result binding transport

The private ABI34 `actql_payload_binding_*` child pins a confirmed original
filesystem Sealed record, its revision and original publication preflight. Its
separately reserved output is limited to 65,536 bytes; the existing buffer Owner
accounts for staging, sealed output and physical copying. Core reconstructs the
original request and calls the existing live Result content-binding Owner,
which checks the exact physical byte count and SHA256 against the original
Result. Python transports the resulting contract without reconstructing values
or semantic fields.

Production and cached reads revalidate the original Run and Source account. A
prepared, opaque, foreign or changed record cannot supply this binding. A failed
production is not automatically retried. Pending cleanup keeps the same child,
allocation and parent pin; only successful cleanup retires the child. Closing
the original record waits for its children. This read-only projection does not
commit a Store, acknowledge publication, issue publisher permission or decide
Run completion. ABI33 artifacts are rejected by the current strict loader;
prior immutable evidence retains its original source and module identity.

## Bounded ordinary transfers

Private ABI82 restores bounded block transfers at the existing Python/Core
boundary. The ordinary installed Host uses up to 16384 bytes for each input,
output, Journal query/row and publisher-fact copy. This is physical transport
of the same original bytes, not another decoder, Owner or authorization path.
The same output/input reservation, fixed original VM and original scoped
reader/transaction remain retained. All existing current checks, full row
comparison, limits, publication facts and physical cleanup rules still apply.

Core obtains only a source-pinned wasm32 payload offset through a private
`#borrow` entrance. Python accepts only the same entered instance's exported,
nonshared fixed memory, checks the complete bounded range, copies synchronously
and checks original currentness/loan identity afterward. No address or view is
public, retained beyond copying or used as a Run, grant or cleanup identity.
An incomplete transfer refuses without caching a partial output. The original
constructor reserves the bounded Host temporary and the small-output overlap
before allocation; the original wire limit, pool and parent remain unchanged.
Insufficient backing refuses instead of omitting that charge. A failure retains
the same original ticket and cleanup duties; no physical ACK follows from
copying bytes.

The separately selected raw diagnostic facade retains `fill`, `byte` and
`read_packed`. Ordinary input/output use `fill_block` and `read_block`; a refused
block never falls back to scalar transfer or an older module. This changes no
wire, CID, schema, pool allowance, fuel or Run/Read law. The block-size bound is
a transfer bound and is not a claim about whole Python/SQLite memory or normal
latency.

## Physical publication metadata transactions

The separately selected raw diagnostic ABI retains the ABI81 transport of up to
seven original output bytes per nonnegative
Int64 scalar. The same instance nonce and original buffer handle are retained;
each selected byte passes the existing Buffer Owner guard. Count, position and
closed/foreign access still refuse without exposing a partial scalar. Python
unpacks only into its already reserved bounded destination and retains the same
output loan through complete copying and physical cleanup. This changes no
wire bytes, parser, authority, pool allowance or per-operation fuel. It exposes
no raw address or memory view and supplies no legacy-module fallback.

The focused raw Wasmtime consumer also checks the external signed Int64 ABI
with independently authored UTF-8/CRLF bytes and a packed value above 2^53.
This unmetered diagnostic establishes neither ordinary Run funding nor a
physical cleanup acknowledgement.


Fixed identity fields use the existing output Owner with their original 71-byte
SHA-256 CID or 64-byte index-key bound. Full contract bodies keep the existing
one-MiB envelope. Both field loans and their physical copies remain retained
through the synchronous Store consumer; a refused reservation or cleanup keeps
the same original children. The bounded scalar constructor does not enlarge
the pool, reduce a charge, grant a read or replace the current original view.
Its declared bound accounts for the actual field and refuses a larger produced
wire. Private ABI80 adds this constructor while retaining the original full
body constructor and all existing parent/current/borrow checks.


The installed Python Host can attach one opaque metadata batch to several
original payload records with `LocalByteStore.compare_exchange_many_attached`.
The existing SQLite byte Store checks every original record's exact bytes and
physical generation, and its exact capacity reservation, after the same
`BEGIN IMMEDIATE` and before any metadata replacement. A missing or changed
original, reservation or expected metadata generation prevents the entire
batch. Original payloads and reservations are not advanced or released.

Core full-chain validation, original Store binding, and current publisher
authority remain prerequisites owned by their existing Owners. This physical
transaction does not parse a contract, decide publication, or assert a Run
state. A lost commit acknowledgement is propagated without repeating writes;
the caller observes exact successors and lets the original Owner decide the
meaning. Schema format 2 and its bounds remain unchanged. Retained caller bytes
and SQLite workspace require their existing Host reservations.

The exact successor of an opaque metadata batch is observed with
`read_exchange_many_attached` under one SQLite read transaction. All original
payload bytes, generations and capacity reservations share that snapshot with
all metadata reads. The method returns the complete exact batch or an unmatched
observation; it never emits a partial prefix or converts a missing/later record
to an absence proof or retry permission. Invalid retained bytes are errors.
Only successful read-transaction cleanup exposes the observation; failed
cleanup retains the original Store handle as pending. Current authorization and
Core interpretation remain separate, and physical process-restart readback is
not proof of restored Run state.

## Independent publisher callback transport

The private `actql_publisher_*` child uses the original checked publication
preflight and an original borrowed Store input, not copied contracts or an SDK
permission boolean. Installation grants nothing. `authorize` selects the
original request or the matching Core-produced commit index, then delegates to
`install_local_preflight_publisher_port`. The existing port revalidates current
Run/Source access and the installed Host fence before and after its independent
publisher callback at every stage. Permission for `return_committed` is not a
Store acknowledgement or a completed public Run.

`publisher_current`, `publisher_begin`, `publisher_byte` and `publisher_finish`
are private scalar imports. Facts contain exactly stage, namespace, authority,
Run, original request and optional original index. Policy and target remain in
the original request preimage. The installed trusted Host must supply the
actual current publisher Owner bound to that original policy/target and Store;
this bridge supplies no portable settings issuer or authorization registry.
Source or Run access cannot implement publisher authority.

The Local supplier retains the original admitted Account configuration body;
its configuration CID must equal the original request's publication policy CID.
The request's target must equal the original private Store authority. Core
evaluates the original Run principal and connection with resource `run` and
operation `publish`, independently of its submission tuple. Both the retained
Account and the current Account must allow publication. The current Account is
reevaluated before and after every callback. A newer Account never replaces the
original policy CID or fills missing original custody. The physical callbacks
remain Host fences and six-field observations, not SDK-supplied grants. A
previously committed index with a different attempt remains eligible for the
existing full-chain validator and `return_committed` scope check.

The six-field transfer is bounded to 8,192 UTF-8 bytes using the existing
encoder. Ordered scalar bytes avoid interpreting MoonBit object pointers.
The existing buffer pool reserves overlapping encoder text/bytes and the
physical collector/decoder allowance before callbacks allocate their transfer.
The physical allowance is conservatively 128 times the transfer limit plus
measured descriptors and container overhead. Independent callback resources
still require their own reservations; this is not aggregate memory accounting.
Budget refusal is unknown, never publisher permission. Callback true, false,
and exception/unknown remain distinct: success is 0, denied permission -35,
revoked current authority -32, and missing original custody or physical callback
failure -36. Original policy/target mismatch is invalid material (-31).
No completed grant is cached between stages.

Parent close waits for the child. Child close blocks new checks immediately,
then retries existing buffer cleanup and the same original input borrow stop.
Cleanup failure retains the original child and reservation. Neither close nor
permission checks submit, execute, resend, or cancel a Run. Remote-only import
has no additional engine dependency. A private bridge and strict caller compile
are distinct from actual Wasm execution, durable Store publication and wheel
acceptance.


## Original commit material projection

Private ABI 36 adds `actql_publication_commit_export_count` on the original
publication and `actql_publication_commit_export_produce_material` on an
existing reserved output child. Both require the original completed validator
view, its exact nominal index, and current Run/Source access. Counting reads the
fixed eight roots and six inventory lengths. Selection uses the original view's
fixed inventory boundaries; it never scans or reparses the inventory.

Each child is fixed to either the existing candidate or one ordinal/field at
first production. A different projection refuses with -33, including switching
between candidate and material. Repeating the same produced projection still
rechecks current access. A failed production keeps its original reservation and
handle until explicit cleanup. Invalid controls refuse with -3; unavailable
original custody/current access or an out-of-range ordinal refuses with -32.

Fields 0 through 3 are exact UTF-8 `wire`, `name`, `identity_field` and `identity`
from the original immutable contract. They are raw fields, without a JSON
wrapper that could double-escape the original bounded wire. The existing
1,048,576-byte output and overlapping physical copy allowance are unchanged.
Python neither parses nor canonicalizes these bytes. A caller reserves, reads
and closes one field at a time; original input/view custody survives until all
children and original physical borrows have stopped. Cleanup failure retains
the same handle and capacity; successful cleanup prevents further reads.

The loader requires the new closed scalar signatures and ABI 36, with no legacy
fallback. These private projections provide no Store key selection, write,
current publisher grant, durable acknowledgement or restored Run state. Actual
Wasm consumption, product aggregate accounting and public Local/wheel acceptance
remain separate from compile and physical-adapter facade tests.

## Original submitted input preparation

Private ABI46 adds preparation kind 3 for the existing SDK submitted-intent
envelope (`kind`, `input`, `parameters`). Core retains the original
`ClientSubmittedIntent` together with the exact `LocalPreparedInput` produced
from that envelope. Run preparation and restoration require that same nominal
prepared input; a separately prepared document cannot replace it. This is input
preparation custody, not durable Submission admission or permission to dispatch.

Structured Program input uses the existing JSON frontend. Query input selects
the existing explicit SQL or AQL-text frontend and preserves its original text,
parameter declarations and supplied bindings. Missing bindings and explicit NULL
remain distinct in the existing Checker. The installed Local profile rejects
other query formats before preparation and does not try another format. No
Source, Compute, Model, Effect or persistent Run operation is started by this
preparation. Earlier module ABIs are rejected by the strict installed loader.

The shared checked-binding validator is the original Native journal's pure
request/prepared/compiled/definition check, reused by Local. Native still owns
its original admission transaction and issuance count; this extraction neither
acknowledges persistence nor grants publication authority.

The original Native submitted Run admission codec is shared with the portable
Host. It preserves the exact `admitted_revision` decimal Int64, original
request record and Run definition CID; decoding requires the same canonical
bytes. The Native journal continues to check the original epoch, intent, Run
record and current authority inside its existing transaction. Parsing these
bytes alone does not establish that transaction's commit or a dispatch permit.


The shared physical journal encoders preserve the existing Native Run row and
submitted-intent row bodies, field omission, Unicode values and byte limits.
The submission epoch Owner supplies the original reference wire, and the
checkpoint and policy Owners supply their original serialized bodies. Encoding
these fields is not admission, a transaction acknowledgement, current authority
or a start permit. Native readmission still validates those original records,
relationships and canonical bytes; its count, epoch and transaction fences are
unchanged. The portable physical adapter must retain those same obligations
before exposing any accepted Submission or Run.


The physical byte Store can fence an original admission batch with exact epoch,
configuration and issuance metadata bytes/generations in the same SQLite
transaction. A count row that is replaced by that batch is checked against its
original preimage before COMMIT, then against the exact successor during
read-only lost-acknowledgement lookup. Other originals remain unchanged. The
installed Host holds Core before Store and separately reserves the retained
projection and SQLite workspace; its current typed port is checked before the
transaction work, before COMMIT and before exposing a successful reply. A fenced COMMIT failure or current-port
failure after COMMIT raises `LocalStorageCommitUnknown`, preserving the same
Store cleanup handle and original cause. It cannot be reported as a pre-write
refusal or permission to repeat the batch. Query and cleanup
failures are exceptions, never unmatched/absent results or replay permission.
The adapter only returns physical generations/raw bytes. Existing Core Owners
still validate original identity, admission, publication and execution facts.

The shared SubmissionReference codec preserves the original Native token
shape, canonical reference bytes and typed nonce identity. A syntactically
valid authenticator is not HMAC authentication. The physical Host still verifies
the original durable key, clock and epoch in the same admission transaction.
Native authentication, journal readers, count custody and transactions remain
separate from this pure codec.

The Local submitted-row preparation binds the exact nominal submitted
preparation to its original checked Plan, request, current Account permit and
context. It compares the retained preparing row with the original encoded
intent and reference before projecting the initial Run row and ready candidate.
It cannot prepare a ready row again, replace an equivalent preparation, or use
a foreign or expired reference. These opaque projections perform no I/O and
prove no COMMIT, accepted Submission or start permission. Before adoption, the
Host must validate complete original journal/count custody, current epoch
authentication and the same physical transaction, then readmit the actual saved
rows through the existing Owners. A lost acknowledgement never authorizes
repeating the candidate writes or reconstructing a new Run.

Private ABI47 projects the original submitted-row candidates through the
existing material output family. Its separate reserve entry binds an original
Run, current Account configuration and input buffer containing the original
reference, retained preparing bytes and observed epoch clock. Ordinary material
kinds remain closed at 1–5. The new entry retains the original submitted
preparation; it does not pair a copied intent with an unrelated prepared Plan.
Core emits physical keys and raw preparing/initial Run/ready candidate strings
using the shared original codecs. The same existing one-MiB output reservation
accounts for transfer and Python destinations before encoding. Encoding or
cleanup refusal does not release the original handle prematurely.

The candidate output closes before returning its input borrow. Cleanup failure
retains the same output, Run, current configuration and borrow for retry;
successful output retirement is not repeated while physical reader stop is
pending. New reads/production of a retired output are refused. No operation
admits a Submission, persists a Run, reserves dispatch, starts Compute, cancels
a Run or commits publication. The Host must still connect the complete original
issuance/count inventory, authenticated epoch, same-Store transaction and actual
saved-row readmission before exposing a public accepted operation.

The shared original Run-row decoder validates the closed retained shape,
request identity, Run Definition and exact canonical row bytes. Its result is
an encoding record, not a retained Run or admission proof. Native readmission
continues to validate Policy, Effect and Checkpoint originals with their
existing Owners, including the original Definition and Effect ledger scope,
then re-encodes the complete admitted record. The shared issuance-count reader
preserves the original canonical decimal syntax and finite profile. A valid
count is not evidence of complete registration: the same Store transaction
must still scan every original row and validate all custody relationships.

The physical Store's inspected batch forwards Owner-selected namespace/cursor
reads synchronously under the same SQLite transaction as the original metadata
fences and CAS. It copies one original row at a time, preserves raw keys,
generations and bytes, and distinguishes the observed physical end from query
failure. The existing record and cumulative copy limits include repeated reads.
A captured reader cannot outlive that transaction or be used concurrently or
recursively; swallowing a query, current-port or consumer failure still aborts
the batch. The Host accounts for Core inputs, retained originals and SQLite
workspace and returns the same transfer loans before requesting another row.

Lost-acknowledgement inspection checks the exact original write successors and
untouched metadata, then forwards saved inventory rows in that same read-only
snapshot. It performs no write or replay. Core must validate complete required
inventories and readmit the actual saved records with their original identities
before an accepted operation can be exposed. Neither a count match, a partial
scan nor the physical callback's return value supplies that evidence. Cleanup
failure retains the same Store transaction; attempted-COMMIT uncertainty keeps
the original Store handle for lookup instead of creating a replacement Run.

The shared submitted-row decoder preserves the original Native reference,
unchecked intent, preparing/ready shape and exact Int64 admission revision. A
decoded ready field is not an accepted public operation. The original retained
relationship validator binds its Reference authority/caller, Request intent,
Run Definition and admission revision to the actual retained Run. A later Run
revision preserves the immutable earlier admission; an expired epoch can still
identify retained history without granting a fresh admission or resend.
Native keeps its actual Run reader, nested original validators, complete
inventory scans, authenticated epoch and SQLite transaction around this shared
validation. Its original codec test adapters are test-only.

Local validation additionally binds observed physical keys/generations and
saved rows to the exact nominal submitted preparation and checked Plan that
issued the original candidates. A changed submitted intent or a merely equal
preparation cannot acquire that relationship. This returns only a relation
check: nested originals, complete same-Store inventories, current authority,
authenticated epoch and physical COMMIT still require their existing Owners.
The returned Unit is not an acknowledgement, start permit or public Run state.

Within one synchronous publication-binding relationship check, the private
submitted-row helper returns its first decoded Run encoding and original
metadata after all existing relationship checks succeed. The public validator
still returns only Unit. Publication binding consumes that same typed result
for its cancellation, Checkpoint and Effect-original refusals instead of
decoding the identical bytes again. No callback or physical operation occurs
between those uses. Each later observation, changed row or CAS successor runs
its own relationship check; no row/revision cache or new proof input is added.
Current authorization, exact prior/successor comparisons and physical COMMIT
remain with their existing owners.


## Original saved-journal physical port

The selected private image uses the original scalar Journal scan and exact-row
requests. A Saved read compares every retained key, revision and complete byte
body in its original Store snapshot. Original typed current checks enclose
each physical query and transfer; no encoded equality packet or retained
comparison result supplies later currentness or permission.

Within one borrowed SQL reader, request blocks and copies of its already-read
immutable row use the Store's private frame check. It checks the exact reader,
active lifetime, original thread, non-reentrancy and latched failure; it observes
no current fact and returns no permission. Scalar diagnostic readers without
this port retain their full current checks. Actual queries still check the
original current before and after I/O, and the Core row consumer checks its
typed current before and after the complete transfer. File, settings, epoch,
Account and authorization checks remain at those protected boundaries. No
frame, row or successful decision survives the enclosing reader.

The actual Store reader encloses the Journal's required current observer in
its existing query and returns bounded immutable row DATA directly. Complete
SQL metadata and original physical-current checks run before physical read and
before returning that DATA. No external consumer runs between those checks:
the Journal only validates and packages the row for its existing ABI transfer.
The generic `read` and `scan_after` paths retain their arbitrary consumer and
all three fences, including the separate post-consumer check. Only callback
identity suppresses an adjacent duplicate observation already performed by the
same fence; a different observer runs separately at every boundary. A private
reader without the direct port keeps the original outer before/after checks.
Neither shape returns bytes after a latched failure, changes query/copy bounds
or turns a physical miss into a semantic absence fact.

The installed Host's own adoption/settings inventories use a closed bounded
comparison in that same reader. At most nine sorted original key/body pairs,
revision zero and the trailing absence query must match. No row escapes and no
caller-supplied consumer runs between queries. The exact stdlib SQLite adapter
with the same required current observer groups physical file observations before
and after that entire comparison; every row still checks the original transaction,
main/TEMP schema, metadata, failure latch and cumulative query/copy bounds.
Current callbacks remain non-reentrant, and even a swallowed callback failure
refuses before the comparison returns. Both complete inventories still run
before and after protected Core work. A reader without the closed port retains
the direct per-row port; absence of both ports refuses. Independent physical
adapters and distinct current observers retain per-query physical fences.

The synchronous publication-observation caller advances its original Owner in
finite 256-unit quanta instead of reopening the complete inspection every 16
units. Each advance keeps a fresh before/after current frame and the same original
response, publisher and file facts. Core caps the quantum at the remaining
cumulative work budget and retains failure/cancellation and cleanup state; the
caller neither refreshes fuel nor finishes before Core reports readiness.

Within that same live reader, the exact stdlib SQLite adapter can retain a
completed immutable metadata-fence observation. Reuse requires the same
physical adapter and connection, unchanged original transaction sequence and
actual main and TEMP schema versions, plus SQLite's unchanged total row-change
count. Both bounded schema-version PRAGMAs still run before and after every
mutable current observation; they are counted separately from metadata-row
queries. TEMP can shadow the physical table without changing the main schema
version or any row, so the two schema observations must come from the same
original connection and transaction. DDL is never inferred absent from
`total_changes` alone. A schema/transaction/connection replacement refuses, and any row
change requires complete metadata validation again. Savepoint rollback does
not reset SQLite's total-change count. Another reader starts without an
observation, and physical suppliers without this exact port keep full checks.

Every physical/current callback still runs, including file/settings/epoch and
Account checks. The typed original-current query uses that same immutable
metadata observation at both physical query boundaries, each with fresh complete
snapshot and mutable-current checks. Its actual physical row is always read;
raw readers and other physical suppliers retain complete metadata-row reads at
their respective query and consumer boundaries. The
outer read/write and precommit fences remain complete. Copy/thread/reentry, retired transaction, callback or
schema-probe failure poisons the same reader. There is no current/Allow cache,
new owner, retry, changed bound, Native ABI, or persistent snapshot token.

The standard original operation metadata callback joins its adjacent current
and required-frame fence checks in one complete observation of the same reader.
It accepts only the captured original current callback and retains the complete
raw/cleanup path. A synchronous submission produce/read handoff likewise uses
the producer's postvalidation as its transfer prevalidation, then validates
again after copying. Standalone methods keep both their original checks. A
failed producer, current or copy leaves the same output/input loans for cleanup;
neither composition caches a grant, refreshes fuel or repeats uncertain work.

One closed six-row delivery proposal validates its locked original Reader
facts around the complete synchronous projection group. The existing Store
owns all six uncommitted CAS writes, then invokes the independent precommit
current/Account/producer checks; COMMIT occurs only after the enclosing
inspection returns. A changed file or failed ordinal therefore rolls back the
whole group. A failed COMMIT still retains the same Unknown attempt and child
cleanup responsibility. No fact observation is reused by another transaction.

### Closed Guest current observation

The existing Guest current record retains the same adopted material, original
Account and adoption bytes, actual original row, Store and generation. Its
physical operation observation remains fresh on every protected decision.
Physical callbacks may retire the Instance or record: liveness is checked both
before and after the actual callback, and retirement clears the observed
operation before refusing. A returned operation number is DATA, not authority.

Only the closed Guest adapter can share that fresh observation with the adjacent
synchronous projection of already-admitted originals. It checks the same
Instance after the callback and compares the original Account, bytes, material,
row, Store value, generation, operation and record state across that callback.
Replacement, reentry changes, retirement or failure refuses; equal copied bytes
or an equal operation number cannot supply another original. There is no query,
external callback or await between the final field checks and the projection.
Common still validates the complete original observation and evaluates Account
Allow or Deny separately for each protected operation.

Raw independent callback ports retain their second physical sample, including
callbacks that fail or change only on that sample. A zero or newly observed
operation retains both actual row queries, physical current and the final
physical sample. This is not an Account/current-success cache, a new phase
carrier, a public author callback or a new capacity allowance. The existing
Guest Instance/current/buffer and imported parent remain the only owners;
retirement and failed cleanup retain their original pending responsibility.

### Consumed installation preparation readers

After the original Host binding has completed its own admission and actual
initial inspection, the same Installation may retire an earlier completed EOF
reader only when its later live Host pin has the same root/name and complete
original physical snapshot, including device/inode, size and digest. Both
original descriptors are physically observed before retirement; the same Host
pins recheck their complete current, including named installation roots, Store
generation and retained files, after the old descriptor closes. The pin keeps its own
original body and descriptor, and every subsequent current still observes it.
This removes a consumed physical preparation read, not a current or Account
check, semantic original, file, immutable byte body or resource reservation.

Unmatched preparation originals remain in the Installation's original reader
list. Ambiguous, copied, foreign, closing or changed pins refuse. Failed or
uncertain close retains the same original reader and pending Installation;
only its existing explicit cleanup may observe that same descriptor again.
Successful close removes exactly that old reader from the existing cleanup
list before post-close observation, so a later refusal keeps all remaining
pins and owners without reopening or double-closing the old descriptor. Saved
files, Store state, canonical material and existing conservative bounds remain
unchanged; there is no replacement pin, authority or cleanup owner.

### Original file observation groups

An original saved reader retains the immutable EOF digest/snapshot value it
already returned. Every later observation still validates its original reader,
root, descriptor and named file before returning that same DATA. It rechecks
any expected generation and digest; mutation, replacement, invalid/closing or
incomplete readers cannot obtain a successful observation from the retained
value. No file/current permission, successful policy or live FD observation is
cached. There is one immutable metadata value per bounded original reader,
aliased by existing Host pins rather than reconstructed for each observation.

Within the existing FileRoot lock, a read-only group observes the directory
before and after all selected original file members. Each member still checks
its exact registered reader, FD, named file, device/inode, size, nanosecond
mtime/ctime, mode, owner and bound on every invocation. The sequence has no
callback, await, read or write. It is a bounded sequence of physical observations,
not atomic filesystem state, an authority grant or another cleanup owner.
Directory/member failure retains the same descriptors for existing cleanup.
Known copied/foreign/duplicate/closing inputs refuse before physical stat.

Host pins use that existing-root group for their complete original member set.
Installation root-path checks remain unchanged; only consecutive original
readers of the same root share the directory checks, preserving their order.
Store generation, settings/epoch, all mutable current checks and protected
query/commit boundaries remain independent. File descriptor limits and original
Host workspace still bound the retained readers and metadata; no replacement
file, new resource allowance, resend or automatic cleanup retry is introduced.

### Initialization component observation

The synchronous initializer performs its complete selected runtime/provider
byte and digest observation after native loading and before Config/Engine
construction. It retains at most those two original read-only descriptors
through the immediate loaded-symbol comparison, then closes them through the
existing one-shot descriptor carrier. There is no intervening native call,
callback, await or new authority. A standalone linkage check owns its own
identical bounded observation; later initializers never reuse it.

The selected image descriptor is bound to the original component's exact
filename, byte length and digest before capture. Its existing bounded reader
still reads and hashes the complete actual file before returning immutable
bytes. The resolver compares that same descriptor instead of hashing those
unchanged returned bytes again. This does not bypass the separate unsafe
Engine/image entrance, native-load checks or standalone diagnostic predicates.

The scope binds the same original recipe and exact runtime path. Before and
after the thirteen address comparisons it checks the retained FD and named
regular file against the original device, inode, size, nanosecond modification
and change times, mode and owner. Replacement, symlinked provider directories,
mutation, foreign/copy/retired scope, or mismatched imported addresses refuse.
The full load-boundary digest, selected library names and ABI/symbol checks
remain independent. File identity does not issue current permission or prove
that code has loaded, linked, executed or retired successfully.

The original initialization scope closes both selected descriptors on success
or failure. An unconfirmed close keeps that same descriptor carrier plus the
original validation and cleanup causes; no descriptor number is retried or
reopened. Initialization failure retains the existing Core/holding cleanup
owner. There is no cancellation permit, persistent path/mtime cache, global
memoization, image cache, new capacity allowance or successful grant retained
past this read-only sequence. Per-file open/hash-byte counters are diagnostic
components and remain separate from uninstrumented Run/Result/Saved timing.

Private ABI 48 connects the original complete journal inspection to a trusted
same-Store physical port. The Core sends a bounded namespace/key request for
`scan_after` or exact `read`; the Host returns the actual raw key, Int64 revision
and bytes, confirmed end/NotFound, or a query failure. It does not choose the
inspection scope, interpret authored rows, compare Run identity, or manufacture
an accepted/committed result. The original Reference, checked preparation, Plan
and row projection remain nominally bound through the existing Owners.

The installed Host holds Core before Store and calls inspection inside the
original fenced SQLite transaction. Epoch authentication, original configuration
and count fences, and the trusted current port remain Host obligations. Current
Account authorization is evaluated by the existing Core Owner before/after the
inspection and before reading the observation. A callback shape alone cannot
authenticate a malicious physical supplier. The port is private Host assembly,
not a public Client permission option.

The buffer Owner reserves the query collector and bounded row-copy allowance
before callbacks allocate it. An original material and its input borrow remain
live until this child closes; parent material/configuration and pool close are
refused while the observation owns them. Query exceptions, Wasm traps and failed
cleanup retain the same ticket/handle/reservation. Cleanup is explicit and
retried through that owner; no transaction, Submission or computation is resent.
SQLite/parser workspace and other concurrently retained inputs still require
their existing separate reservations. This port's finite collector allowance
is not a claim of complete global memory accounting.

The ordinary installed Host separately selects at most 16,384 namespace or
publication queries per inspected transaction. This work ceiling includes
repeated exact reads and end probes; it does not increase the Store's 1,024
persisted-row capacity, 1 MiB row bound or 8 MiB cumulative-copy bound. The Core
may validate the same saved original at several stages of one observation, so
persisted row count is not a bound on that operation's query work. The existing
outer operation fuel remains independent. Exhaustion latches the same failed
transaction and refuses CAS; there is no budget refill, reopened inspection or
resend within it. Private callers that omit the work selection retain the old
query ceiling equal to their configured row count.

The first connected profile validates Effect-free, checkpoint-free saved rows
and a completely observed empty cancellation inventory. Missing custody is not
initialized. Nonempty cancellation, checkpoint or Effect-original paths are
explicitly unsupported until their original validators are connected; their
obligations are never omitted to report success. Full Run, Effect-response,
Receipt and submitted-intent inventories remain mandatory. The observation
keeps the original immutable admission revision separate from the observed Run
and Submission revisions. Preparing and unresolved history remain distinct.

Successful private inspection is neither a COMMIT acknowledgement nor dispatch,
physical-start, retry, publication, Result-read or resource-release authority.
Store ACK, the public Local Client, restoration and externally installed wheel
acceptance remain separate required product connections. The raw diagnostic
retains its 100M lifetime fuel; the ordinary Host uses the operation policy below.
Existing capacity bounds are unchanged. Earlier private ABI modules are refused
by the loader and installed manifest; no repository/Node/CLI fallback exists.

## First-adoption bootstrap metadata

The private ABI49 `actql_bootstrap_*` output calls the existing Common product
factory with its packaged source-free assets. Its closed input contains only
`configuration_root` and `observed_at`. The bounded output carries the five
original Account/retention/Store/Result Policy bodies plus the original checking
environment and the existing Compute configuration. It contains no authority
scope, permission, adopted state, Run admission or durable acknowledgement.

Reserve accounts the existing 1MiB collector and both physical copy allowances
before the factory copies anything. The original input stays borrowed through
producer refusal, interruption and cleanup. Raw buffer/parent close and pool
close refuse a live bootstrap child. Output cleanup succeeds before its input
borrow is returned; failure keeps the same handle for explicit cleanup retry.

The trusted installed Host uses this metadata only for explicit first adoption.
Reopen, attach and resume restore the saved originals and never regenerate their
policy, expiry or identity from current defaults. Installed component selection
remains lazy, exact-cohort and exact-ABI. The raw diagnostic retains its 100M
lifetime fuel; ordinary operations use the policy below. Existing capacity
bounds and independent public Local/wheel/Store-ACK acceptance are unchanged.

Saved originals are read through the existing `LocalFileRoot` physical Owner.
`open_original` retains a nominal descriptor and the observed device, inode,
size and timestamp generation of the private, owned regular file. Reads use
one explicitly released chunk at a time, at the root's existing chunk limit,
with a maximum original size of 1MiB. Descriptor and original-name observations
are rechecked before and after each read and before a cached chunk is reused.
Unicode, line endings, JSON values and absent fields are not interpreted or
normalized by this port. The Host reserves transfer and retained-byte workspace
before opening; file size and descriptor limits alone are not global memory
accounting.

Short reads, changed generations and acquisition failures retain the original
handle for cleanup and supply no completed observation. Closing after input
cleanup stops that descriptor without deleting or rewriting originals. An
uncertain stop retains its chunk and root capacity; retry observes the same
descriptor without another close or open. Physical EOF/digest is neither
adoption nor current authority. The existing Common adopted/current material
must still validate the original Account and actual same-Store adoption row,
and publication requires its independent current publisher and durable ACK.

The same `LocalByteStore` retains its original database and parent-directory
device/inode observations. `observe_generation` rechecks private ownership and
those original generations without SQL, writes, adoption or replacement. It
can supply physical facts during the original namespace-reader transaction;
it neither validates that transaction nor bypasses the reader's thread, fence
and lifetime checks. Normal SQLite writes preserve file identity. Changed,
missing, public or symlink names fail without opening a replacement Store.
The trusted Host must hold the original exclusive root custody throughout;
this path observation is not an independent proof of a SQLite descriptor's
identity against an adversary controlling that root. The Common current port
still requires the actual original adoption row, saved settings/intent and
Account bytes and independently checks current authority. File/query failure
does not prove absence or authorize resending an unknown operation.

The Common original-material codec delegates the existing Native ordered
custody record encoder/closed decoder and configuration-selection encoder.
It preserves the original domains, field order, raw UTF-8, unsigned device/inode
values and 8KiB/64-node record and 8KiB/128-node selection limits. Native keeps
selection, current checks, locking, physical persistence and digest issuance;
its original wrappers retain their existing failure classification. Neither
encoded metadata nor a matching body/CID is a Host adoption or permission.
Python supplies physical observations to these codecs rather than defining
another scope/preimage or repairing saved originals with current defaults.

## Original adopted/current transaction frames

After observing every original file FD/name, root and Store generation, the Host
may consume the exact same frozen snapshot object retained by that reader.
Distinct snapshots still require their complete value comparison. Object
identity never bypasses the preceding physical observations, nominal ownership
or retirement checks and is not a reusable currentness result.

The borrowed namespace reader reuses shape and bound admission only for the
same immutable fence objects in the same admitted order. A newly constructed
outer tuple may hold those exact objects; equal copies, reordered members and
subsets still take the complete required-fence validator. Each call first
observes the actual current transaction and both schema catalogs. Successor
writes still prevent selecting the prior fence as current metadata. This
shares only immutable DATA validation, never a currentness or permission result.

Private ABI50 `actql_current_*` retains one original metadata input and one
physical query/cleanup ticket. Core chooses the `client_local_adoption`
singleton scan and validates its exact key, revision, original body and unsigned
device/inode through the existing Common adopted/current material. The physical
port must retain the actual same Store and original filesystem, settings, epoch
and transaction fences; neither JSON nor a callback shape authenticates a
malicious Host. This connection does not initialize or repair adoption.

The Host supplies its namespace reader only during `host_current_frame` under
the original transaction/thread. Every bind, scope production, length and cached
copy revalidates current, and the reader is detached even after failure. Current
scope metadata contains the original Account bytes and Core-issued Account and
authority-scope CIDs. It is neither Account Allow nor execution, Result read,
publication, durable ACK or retry permission. Reuse outside a live frame, through
another Store, copied loan, closing instance or retired buffer is refused.

The Python physical current callback checks exact retained file membership and
observes each complete source/state file group once per callback, under that
group's existing lock. The observation still includes every pinned descriptor,
the original root and Store generation. Membership checks do not read bytes or
issue permission, and return no token that can carry currentness to another
callback. The next callback observes the physical originals again; Account,
epoch, namespace and Core-loan checks retain their independent boundaries.

The original Host retains its bound current observer once and forwards that
exact callable through its inspected Store operations and Journal loans. A
namespace reader combines `check_fences` with that observer: each invocation
still completes the original current check between both SQL metadata fences.
Only the exact observer already invoked by that same reader is covered; a
distinct callback runs separately and must return no permission value. The
combined checker is required by the private reader contract; missing code is
refused rather than selecting another dispatch path. This retains no successful
observation across calls or transactions. Changed rows,
copied or expired readers and callback failures retain their original refusal
and cleanup duties; Account and publication authority remain independent.

The existing Store supplies this reader with `inspect_namespaces`, using a
read-only transaction and the existing bounded/failure-latched reader and
physical fence validator. It performs no write or COMMIT. Failed transaction
cleanup keeps the same connection pending; no partial observation escapes and
cleanup is not automatically repeated. Query failure remains distinct from
confirmed scan end and cannot prove absence or nonexecution.

The existing buffer Owner reserves output and raw query copies before I/O.
Output repeats the account string already present in the immutable input plus
two fixed CIDs, bounded by that serialized input's size plus 256 bytes. Separate
holding covers both 262KiB raw-row copies. Full close succeeds at output cleanup
before returning the original input borrow; failure retains the same ticket and
parent. No global memory, full Host adoption, public Local, runtime/wheel or
Store-ACK completion follows from this component connection. Raw diagnostic
100M lifetime fuel and original Root limits are unchanged; ordinary Host fuel
follows the operation policy below.

Private ABI51 adds `actql_run_install_current_configuration` for product
assembly. It uses the original live `actql_current_*` material and only the
retained namespace and original Result Policy setup input. The existing Common
Owner supplies Account and authority scope; its original Account CID is the
policy CID and its scope is the authorization context, matching the Native
product setup. Python cannot supply replacements for those CIDs or the Account.
The existing Result Policy Owner still admits the exact original body/CID.

The typed configuration retains its current parent and input. Parent close
rejects while configurations use it. Preparation, restoration, submission
projection, dispatch/start, Source-free Compute and publisher callbacks recheck
the same current material before protected work. Cleanup retains its existing
paths when current is unavailable. This configuration is not a Run acceptance,
publisher grant or Store ACK. The low-level trusted configuration entry remains
for existing private component/Host uses; product Local assembly does not use
it as a fallback. Public assembly and real runtime/wheel acceptance are separate
remaining connections.

Private ABI52 adds `actql_original_*` for the existing initialization,
configuration custody, journal custody and selected-settings preimages. Core
admits original Account bytes and emits original bodies/CIDs; Python supplies
bounded raw bytes and physical generations. Native delegates only the ordered
record encoding, retaining its original nonce, crypto errors, IO and current
checks. No original is repaired or reissued during restoration.

### Project and profile metadata

The same metadata family admits project configuration and profile selection
through `admit_client_project_configuration` and `select_client_project_profile`.
The retained input contains the original configuration wire or explicit absence
and the original profile override or absence. Core retains that same nominal
selection before fallible encoding; the eight-field locator projection is DATA,
not an installed Source, Model registration, permission or funding promise.
Python preserves the explicit `mock_catalog` locator and ordered task/answer
locators and performs no profile rewrite. The catalog locator uses the same
original file acquisition and retirement as the other project inputs.

The existing Core lock and bounded input/output loans cover this preparation.
A failed parse, copy or cleanup retains the same child; it is not prepared again.
Output cleanup and input-stop acknowledgement precede selection retirement.
Retiring the selection drops managed references and does not prove physical
Host, Store, Run or capacity cleanup. Profile installation must consume the same
retained original and still supply actual configuration/currentness and complete
constructor/continuation backing. It cannot recover that original from equal
serialized locator DATA. The intake has no authority or asynchronous callbacks.

The project metadata whitebox cases cover absence, original overrides, ordering,
foreign equality and retirement; Python loan cases cover immutable projection,
copy refusal and failed cleanup. They do not establish an installed Mock run.

### Named Local project preparation

The named sync and async Local `connect` entries capture the optional profile
and call the same private installed-factory assembly as `open`. `open` retains
its explicit Store-only selection, including Saved-first clients. Remote
construction and explicit signers retain their existing paths. A project is
neither an endpoint nor a source of signer, Account, permission or capacity.

The factory acquires the same installed Core before project IO. The Host then
retains the physical project child, exact configuration input, Core metadata
child and nominal profile selection before fallible preparation or Store
initialization. Referenced inputs use the same configuration directory and
original locator order; multiple roles selecting one exact path retain the same
physical member. Explicit `installation` wins; otherwise the original Core
`state_dir` is relative to the selected configuration, including discovery in a
parent directory. Merely copying locator DATA cannot install a profile.

The existing Host lock and cleanup sequence own these loans. Metadata retires
before its Core input, and the physical project child retires after its consumers
and installation and before the Core. Constructor failure returns that same Host
without re-reading inputs or initializing another Store. Uncertain physical close
retains its child through the original acknowledgement; coroutine cancellation
does not acknowledge it or cancel a Run. Project workspace and separate Core
input/output reservations cover the simultaneous constructor and retained files.

Fresh preparation observes the same physical group and retained Core selection.
The selected profile still needs its actual published or Mock environment and
executable owners. It cannot execute against the source-free bootstrap merely
because intake succeeded. Saved Run lookup/restoration continues through its
separate original-material path, without submitted preparation or profile
replacement. The physical worker binds the same narrowed original Run and
method before asynchronous work, independently of the requesting coroutine.

Component cases cover actual project/File/Store custody with explicit semantic
Core ports and public sync/async factory forwarding with an explicit Host port.
Their scope is distinct from an installed Mock/Effect/approval execution or
external ABI/distribution qualification. Existing typed consumers and canonical
interface declarations cover the same public profile option and private callers.

### Original project file inputs

`OriginalLocalProjectFiles` supplies bounded read-only physical input to the
same configuration preparation. It reserves its Core workspace before opening
directories or files. Its limits cover simultaneous raw, destination, text,
path and descriptor holding; the subsequent Core input and metadata loans are
separate. It does not parse project JSON, select a profile, install a provider,
issue authority or start a Run.

Project directories are ordinary read-only directories, distinct from the
private, exclusively owned Store roots used by `LocalFileRoot`. Reads retain
the same open parent and regular-file descriptors, original named generation,
size and timestamps. Bounded nonblocking acquisition refuses symbolic links and
nonregular files. A whole-group current check precedes returning retained bytes.
The nearest `actql.config.json` is selected only after observing its bytes;
each nearer acknowledged absence remains part of that original group. A new
nearer file, replacement, changed generation or unreadable input cannot become
an empty/default configuration or trigger parent fallback.

The installed caller owns this child and serializes it with the same Core lock.
Failed acquisition retains its original descriptors and workspace, and the
failed input cannot be read again. Cleanup uses the existing descriptor-uncertainty
rule: an uncertain close is observed, never repeated on a potentially recycled
descriptor. The original Core workspace acknowledges physical descriptor cleanup
before the retained bytes and references are dropped. A trapped reservation
keeps its original ticket until the same Core completes global cleanup; even
then, any still-held descriptor prevents a fabricated acknowledgement. This
cleanup does not cancel a Run, acknowledge Store durability or remove named
files. Actual POSIX discovery, generation, bounds and failed-close cases cover
this port with explicit Core workspace ports; they do not qualify installed
profile execution or the external Wasm ABI.

One output reservation retains its original input borrow. Output cleanup must
succeed before that borrow returns; failed cleanup retains the same handle.
`LocalHostFiles` pins exact saved descriptors and the original Store generation,
rechecking them before returning retained bytes. Acquisition or stop failures
retain the same physical handle for explicit cleanup. It preserves saved names,
Store and Run custody and does not parse JSON or issue a permission boolean.
Its raw-byte limits require the assembly's simultaneous workspace reservation;
they do not establish global memory accounting. Full saved intent/settings and
adoption validation, the public Client assembly and actual Store ACK remain
required beyond these metadata and physical ports.

`OriginalHostBinding` supplies the same saved originals to the existing
Common adopted/current material through a read-only SQLite snapshot. Trusted
assembly supplies the four original Core projections, exact source/staged
Account files, custody files and selected settings. The binding retains their
loans and checks their exact saved bytes; it does not issue those originals or
reconstruct their identities. The existing Common Owner still validates the
actual singleton adoption row, Account and scope and makes operation decisions.

The snapshot fences the original selected manifest/file rows at revision zero,
their complete namespace membership, and the physical epoch key/clock row.
Epoch observation performs no projection or clock advance. Explicit clock
progress is observed by the next snapshot; replacement keys and backwards
retained clocks are refused. Core, original File roots, then Store are locked
in that order. The query reader is detached at frame exit and cannot be reused
for protected work outside the snapshot. No fresh write transaction begins in
this read-only frame; existing pending-write confirmation remains separate.

Live close seals new work and keeps these loans until frame exit. Failed output
cleanup retains the same current/input/workspace handles. A reserve trap without
a returned handle retains its exact physical ticket and requires the original
instance's actual retirement; it cannot be repeated or called complete. Closing
this supplier does not cancel a Run, close the caller's Store/files or repair
adoption. Actual initialization, publication ACK, public Client/runtime and
installed-wheel acceptance remain required parts of the product assembly.

The same binding can lend its physical fences to the existing Store's inspected
CAS or successor-lookup operation. `fenced()` holds Core/File custody but starts
no transaction. The caller includes every returned fence in the original Store
operation and supplies `inspect_reader` within that operation's inspection.
The physical reader checks its exact original object, lifetime, thread and
required fence coverage before Core receives it. Copies, expired readers,
another Store or missing adoption/epoch fences cannot borrow current material.

Core's current frame exists only during the original inventory inspection;
its reader detaches before physical CAS/COMMIT. Precommit and postcommit physical
checks do not become Account Allow, publication success or a durable ACK.
Saved-row readmission and `return_committed` use a fresh original read snapshot
and the existing Core full-chain/publisher validation. COMMIT-after-ACK-loss
remains Unknown with the same Store; its exact successor can be inspected
without repeating the original CAS. Rollback failure keeps that original
connection pending and prevents a new frame until explicit physical cleanup.

Initial trusted assembly can acquire the empty DB through the existing File
Owner, bind its actual device/inode into the original journal custody, and
persist the initializing marker before opening SQLite. The physical Store's
`initialize_owned_file` consumes that exact exclusive empty-file handle once
while retaining the same root lock and writer for cleanup. It does not accept
a boolean, copied handle, renamed file, another directory or a later pathname
as a creation claim. SQL failure does not restore the consumed acquisition.

This entry creates only the existing physical schema. Epoch keys, settings,
adoption and original Core validation remain separate assembly obligations.
A reopened empty DB without that original acquisition cannot create a schema
or recreate lost keys. After successful SQL setup, the original writer cannot
resume payload operations and is stopped explicitly; uncertain stop retains
the same descriptor/root capacity. Neither physical schema setup nor the
one-time creation claim is Host adoption, Run admission or public acceptance.

`OriginalLocalInstallation` composes these ports for the installed source-free
profile. Only an empty private installation directory takes the first-bootstrap
path. Core supplies the seven configuration originals and original selection,
initialization, configuration custody and journal custody bodies. The physical
DB file is acquired and its initializing marker synced before schema/key IO.
Key, selected settings, initial counters and adoption are persisted together in
one physical transaction. Their existence still requires Common's actual
adoption/current validation before protected work; physical COMMIT is not a
Run, publication or durable Result acknowledgement.

Reopen never invokes bootstrap or updates policy/expiry. It reuses exact saved
bytes and rechecks the original directory, file and Store generations, marker,
settings membership and epoch custody. Missing/partial material or changed
Source/Result roots is unavailable, not repaired. Unknown initial COMMIT keeps
the same Store and originals; later reopen inspects them without repeating the
initial batch. Setup encoding, raw-byte/descriptor and SQLite workspace loans
remain held until their original cleanup succeeds. This assembly does not own
the Core instance, start Source/Compute/Model/Effect, cancel a Run, or constitute
the installed public Client/wheel acceptance gate.

The Client's private `_connect_local` route consumes the installed Host's
in-process operation/response port without constructing an HTTP endpoint,
token or network client. It fixes `mode=local`, `owner=local` and durable
connection selection; negotiation and every operation continue through the
existing closed wire validation and the same async/sync Execution/Result models.
Response collection, reader cleanup and failed-close retry share the existing
transport custody. An in-process exception after an operation begins remains
Unknown and never triggers replay. This route supplies no scope, Allow, status
decision or execution implementation. Installed factory/public `open`, original
Owner wire projections and the actual public runtime/wheel scenario still have
to connect before this is a delivered Local Client.

Private ABI53 exposes the original saved admission through
`actql_journal_admission_length` and the existing reserved buffer transfer.
The existing retained-Run validator's nominal inspection is held with the
actual same-Store snapshot; definition namespace, request authority scope and
immutable admission revision come from those originals. Preparing/missing
observations cannot issue this view. The full Int64 remains in the journal; an
unsafe public JSON revision is refused rather than rounded or replaced by a
later Run/control revision. No wire/schema version or identity preimage changes.

The original current/epoch/configuration frame is checked before producing or
reading cached admission bytes, and after production/physical copying. Python
attaches only the original same-Store reader for that call and detaches it on
all exits; exceptions and cleanup failure preserve the same parent/ticket.
This read-only transfer issues no new admission, COMMIT ACK, dispatch permit,
publication or Result. The durable Host's actual saved-row observation and
current authority are separate from its write candidate and later control
state. Installed public Host assembly and wheel acceptance remain separate
from this private bridge.
# Original submitted-intent append projection

Private ABI54 adds submission projection kind 3 and
`actql_submission_validate_append(nonce, handle, current) -> i32`. The original
typed current configuration supplies its same-Store namespace-reader callback.
The physical Host authenticates the exact epoch before projection; Core checks
its authority scope and validity, the original complete Run and submitted-intent
inventories and the existing empty-cancellation profile, and the existing saved-row validators. Core then
emits either the retained original row or the original issued-row CAS and
preparing-row insertion candidate. Neither output is a Run admission, permission
to dispatch, physical write, COMMIT acknowledgement or resend permission.

The existing BufferPool reserves the candidate output and physical copies before
production. Validation rereads the actual transaction's inventory and compares
the original candidate before cached transport reads and physical CAS. A changed
candidate, wrong current handle, closed input/output, unsupported Effect custody
or query failure refuses without silently narrowing the inspection. Nonempty
cancellation custody is explicitly unsupported at this connection and remains
part of the product cancellation work. The Python
assembly submits the two original writes through `compare_exchange_many_inspected`
in one fenced SQLite transaction. COMMIT uncertainty retains the original
Store and loans; it does not replay the writes. Explicit lookup is separate.

This projection does not issue a finite Run Policy. First acceptance must select
the adopted Common finite profile and persist its original issuedAt/Policy packet
with the original Run/intent transaction. Lookup and restoration reuse that saved
packet without extending prior Result, grant or receipt deadlines. Those Owner
connections and actual runtime/wheel acceptance remain separate from this ABI's
compiler and scalar physical-port checks.

### Explicit SDK first-install selection

Private ABI55 adds `actql_bootstrap_produce_sdk`. Its explicitly selected factory
retains the seven original bootstrap bodies and adds `run_policy_profile` and
`sdk_read`. The original producer's seven-field output is unchanged. A loan
cannot switch producers after invocation; SDK and original transports have
distinct nominal Python families. Installed component admission requires the
matching ABI rather than falling back to an older module.

The Common delivery metadata Owner issues the closed
`actql-local-sdk-result-read-selection/0.1` body and its exact-byte SHA256 CID.
It selects principal `local-cli`, connection `local`, Result `answer`, purpose
`python-local-read`, sink `sdk-rows`, existing `jsonl` serialization,
`max_bytes=65536` and `max_uses=1`. It binds the original finite profile and data
Policy CIDs. Sink selection introduces no new Result format. Metadata admission
is not Account authorization, a grant, a delivery attempt or durable acceptance.

The SDK factory persists nine source originals, with exactly eight selected
files excluding Account. Each of the two extra originals is limited to 8192
bytes during acquisition and pinning. An additional 131072-byte shared workspace
reservation (eight times their combined maximum) precedes producer or physical
acquisition, including restoration. The existing bounded producer output/copy
reservation remains separate; no selected-file, byte, fuel or pool ceiling is
increased. Failure retains its original loans. Missing finite/read files in a
saved installation do not trigger rebootstrap, adoption or an automatic upgrade.

No absolute read expiry appears in the SDK read selection. Initial acceptance
must bind its exact CID, original adoption, reference/request and Run Definition
in the saved Common policy packet and commit it with the original Run. Lookup
precedes new issuance. Read expiry comes only from the Common-admitted saved
packet; current Account permission, original selected file generations,
committed index/manifest/retention and grant usage remain independent checks.
Whole-process, compiled-module and SDK non-buffer accounting is not established
by these bounded metadata reservations.

## Private packaged Runtime C binding

`scripts/local-native-runtime-binding.json` describes the existing transport
roles, units, argument order and borrowed/owned output slots. Its callback root
is the exact existing MoonBit `register_original_packaged_runtime_roots`
declaration. `scripts/generate-local-native-runtime-binding.py --check` checks
that root and the C implementation parameters, then compares the generated
`packaged_runtime_abi.generated.h` and `_local_native_runtime_abi.py` read-only.
The compiler independently checks the callback prototypes against regular
Native C emission. Same-width UTF-16 pointer/count pairs retain their distinct
root, source, platform and manifest meanings.

The C calling convention is the platform C ABI. The private declaration version
and SHA256 bytes are physical binding identity, independent of Wasm ABI, package
version, permission, original key/claim identity and public wire. A missing or
different binding refuses before a Runtime Owner operation. It cannot authorize
loading a library: the trusted original installer still selects and verifies
the same library, Host and parent-read originals first. No callback, cleanup,
unknown-outcome or final-ACK semantics live in the generated binding.

The serialized original Host thread owns entry. Inputs remain borrowed through
synchronous callbacks and cannot reenter. Owned reply/output slots persist
through transport failure. A known refusal and an unconfirmed physical outcome
remain distinct. The existing inner Runtime close ACK clears only its data;
outer original Root/Reader/Host retirement still requires its original Owner's
separate stop/cleanup acknowledgment. No pointer is a public integer identity,
serialized wire, authority, or permission to recreate a missing original.

An already claimed original Host Read/SQLite pair can supply the private
packaged Runtime capture entrance. The Runtime retains that exact pair and
original Read; it neither claims another consumer nor creates another Read
context. Every capture and current check enters the pair's existing Read phase,
checks the captured Roots against that original physical context, and leaves
through the same phase Owner. A foreign, retired, active or unclaimed pair
refuses without falling back to the standalone capture entrance. A known pair
refusal remains distinct from an unconfirmed Read-child outcome.

SQLite work and Runtime Read work use their separate phases. Normal Runtime
Read may resume after a transaction while the original read use remains live;
SQLite cleanup that stops that use does not authorize another normal Read.
Runtime aliases must retire before outer pair cleanup, and its inner close
acknowledgment does not substitute for Root FD, managed alias, Library,
context, domain, loan or Host retirement acknowledgments. Failed phase leave
and partial capture retain the original cleanup carrier.

## Private Native transport declarations

The installed Native control component's named C shim definitions are the
authority for the private scalar transport signatures. The existing headers
and MoonBit registration roots retain the opaque callback types and calling
convention. `scripts/generate-local-native-shim-bindings.py` derives the Python
ctypes signatures and a C redeclaration header from those definitions; its
read-only `--check` is part of the private provider producer. The generated
`PARAMETERS` and `ORIGINS` entries retain parameter roles and source locations,
so a same-width argument reorder changes the binding even when its machine
signature is unchanged.

The generated binder only configures an operation on an already selected
library. It cannot load or adopt a provider, create custody, authorize a call,
retry a physical operation, or determine whether cleanup completed. The
existing Control, Backing, Domain, Parent Read, SQLite, Database, Lookup,
Live Channel, Worker Selection and Packaged Product custody classes continue
to enforce original-library identity, thread/reentry rules, persistent output
slots, Unknown outcomes and same-carrier cleanup. UTF-16 parameters carry code
unit counts; byte buffers and their byte capacities remain separate. Their
per-operation bounds and refusal classifications stay in the existing shims
and owners rather than in a second generated policy table.

The generated C header is compiled against the original shim headers and
definitions. The independent signature fixture preserves the existing
caller-selected declarations. Actual component probes remain necessary:
declaration freshness and C syntax alone do not establish physical custody,
runtime compatibility, ordinary funding or installed product acceptance.

## Original Native process transport

The same installed process can relay a stop request to its original captured
Holder child. That operation returns only whether the existing termination
request was confirmed relayed. A false or lost response is not stop, and a true
response is not transport return, process retirement, region/FD cleanup or an
external operation outcome. The private reply keeps request observation separate
from the typed stop observation, under their respective exact operation tags.
Foreign, unstarted and retired carriers cannot select a replacement child.
The caller separately returns its original transport borrow, observes the same
Owner's typed stop and obtains the physical retirement acknowledgements. Logical
Host closing must not erase that original cleanup responsibility. A lost foreign
call retains the same sticky Unknown and cannot automatically resend the request.

The private installed assembly retains the existing Native process Holder,
region and imported child frame in their original Host/domain before physical
preparation. Python transports the same opaque references through persistent
caller-owned C slots; it does not construct a process Owner, quota, retry ledger
or recovery controller. Domain retirement remains fenced while this custody or
its unconfirmed reply remains. A no-process typed preparation refusal can drop
only its extra original aliases. Actual process/IPC stop, captured FD/mapping
cleanup, logical quota reporting and business outcomes remain separate.

Private child arguments use NUL-terminated UTF-8 fields, with an empty block
representing no fields and a terminated empty field representing an empty value.
Environment fields alternate name/value. Invalid UTF-8, incomplete fields or
counts beyond the existing Holder's 255 arguments/four environment entries
refuse before physical child capture. The same Holder validates the closed
selected environment, keeps its own duplicate of the original captured region
FD, and snapshots its inputs. Neither C nor Python copies a managed Array
layout, reconstructs backing from a path or turns an FD into launch authority.

Known local thread/reentry/busy refusals precede the uncertain foreign-call
catch. Once a foreign operation can have consumed an original, a lost response
retains that same partial carrier and sticky Unknown; a cleared mutable slot is
not success. Typed same-original cleanup acknowledgment is required before data
aliases and their parent registration can retire. A successful child receives
FD4 through the original process Owner, which retains the pin until typed stop
and physical cleanup. EOF, PID absence, cancellation, thread join or a local
Python close flag cannot substitute for that acknowledgment or prove that an
external operation never occurred.

This private transport requires separately funded original process, descriptor,
control and runtime responsibilities. An arena domain or compiler declaration
does not cover unrelated allocations, admit a VM or supply an ordinary funding
profile. Missing complete normal funding remains unavailable.

## Native image-compiler ABI inspection

The image compiler consumes the same generated scalar declarations as the
Python Core wrapper. Its C signature tables are another projection from the
existing Wasm ABI generator, not a hand-maintained export list or permission
owner. The C-API inspection uses official opaque import/export/type accessors;
it does not depend on Rust or MoonBit managed object layouts. Imports remain
closed to their original module, name and signature, and exports remain closed
to the declared functions and the single bounded, unshared32-bit memory.

Inspecting a compiled module's type shape does not instantiate it or call its
ABI-version export. The original module/compiler/source/link provenance still
binds the image preparation. Successful serialization or type inspection cannot
substitute for the final producer's same-module physical/workspace/Result
evidence. All C-API handles and returned type vectors require the same original
provider scope and keep their original ownership through deletion; process
retirement and any process-static runtime allocations remain with the existing
process Owner. A C header projection or syntax check supplies none of these
physical acknowledgments or missing normal funding.

The private compiler's C configuration is projected from the same validated
Engine-setting sequence used by the Python image producer and runtime. It binds
the original module, source and both library digests. The projection neither
creates native objects nor admits their resources. The caller must acquire the
original physical scope before creating Config or pooling objects, retain both
through a target-setting error, and delete both in that same scope. Attaching
pooling settings copies them; it does not transfer ownership of the pool.
Configuration preparation is not Engine creation, compilation or the final
same-module physical acceptance required by the producer.

The private C compiler receives the same child backing descriptor and waits
for its original parent's binding before entering that holding. Module input
is captured through the existing same-FD bounded digest/seal operation before
Config construction. Compilation inspects the complete generated ABI before
serialization; it never constructs a Store or instance. The output is a fresh
private artifact, not a runtime admission or a replacement physical receipt.
Target errors, partially captured input, original native handles and failed FD
close remain with that same call. An unconfirmed close is never replayed.

Engine deletion does not retire process-global Mach/Rust storage. A successful
compile may therefore report the original allocation-level holding close as
Busy and retain its actual pointer. This is RuntimeRetained, not Released. Only
the original process Owner's later confirmed execution/IPC stop and same-region
mapping/descriptor retirement can discharge that responsibility. Image bytes,
child exit status and thread join supply none of those acknowledgments.

A normal child borrow return leaves the original allocator closing and its
one-shot borrow history intact. After the same process Owner confirms typed
stop in the original empty physical scope, both never-borrowed startup and
normally returned custody follow the existing allocation-level domain close,
then view and descriptor cleanup.
Returned metadata does not bypass live-allocation or scope checks. A retained
original child borrow continues to use the separate stopped-region path; PID
absence cannot select either path or clear responsibility. Failed view cleanup
retains the same process record and its completed domain-close phase.

The maintainer compiler's parent preparation explicitly initializes its selected
Native component before requesting a Host or domain. The component publishes an
opaque process-lifetime record into the caller's original empty slot before
calling its own emitted initializer. This one-shot entry admits no replacement
callback. An occupied slot, another attempt, reentry, a foreign thread or an
inherited record after fork cannot initialize or adopt that original again.
Existing or partially registered original control roots also refuse before
the emitted initializer; an older direct call cannot bypass the one-shot rule.
Initializer failure and lost response retain the same slot and library; neither
the Python assembly nor C resets the component and retries its initializer.

This control storage remains in the already declared initial control envelope.
Its existence or successful initialization issues no Ledger, capacity, arena,
permission, process-stop fact or numerical profile. The subsequent Native
bootstrap still creates and reserves the original resources before acquiring
the actual backing descriptor. Missing initialization ABI refuses; it cannot
fall back to assuming that an already loaded component was initialized.

Closing the compiler parent retires only its confirmed Host/backing/domain
responsibility. It keeps the original process record and library alias; there
is no initialization-record close that could acknowledge process-global Runtime
storage on Engine deletion or arena retirement. That storage remains the
existing process/runtime Owner's responsibility through actual process stop.

### Original interpreter startup input service

The Python Host's selected initial input service binds the actual CPython
3.12.12 interpreter and its RAW, MEM and OBJ allocator callbacks and contexts.
It observes those original services without replacing an allocator or calling
raw allocation/free callbacks on Python objects. The selected filesystem codec
is UTF-8 with surrogateescape. Same-process, original-thread, interpreter,
build and allocator correspondence is checked before and after the bounded
state-directory encoding. The exact str receiver uses its immutable builtin
UTF-8/surrogateescape encoding primitive, not an ambient replaceable filesystem
helper. Exact text is retained alongside its encoded bytes;
PathLike callbacks and unbounded input copies are not part of this entrance.

An attempted copy is not retried after failure. The same error retains the
input carrier. Retiring this bounded input only spends that carrier; retained
byte aliases, interpreter pools, shared modules and process-lived controls do
not acquire a physical retirement acknowledgment or reusable byte credit.
These controls remain separate from backed Native/worker/VM resources and
execution delegation. Initial input service admission cannot authorize cohort
discovery, loader work or a worker when their complete original supply and
import/binding overlap are absent. The ordinary Host factory retains the same
initial carrier on that unavailable outcome.

The public Local method establishes this input original before importing the
Local Host assembly. Its lightweight funding-error port does not import the
concrete Core or distribution readers. The factory adopts the same captured
input once, without recopying or constructing another baseline. A foreign input
or repeated adoption refuses. A partial Host import retains its original cause
on that carrier and spends normal preparation; cleanup-only input retirement
does not acknowledge shared module or interpreter-pool retirement. This orders
the initial-input-to-Host-assembly edge, not the whole public SDK import prelude
or the separate Native/worker supplier.

### Python initial Native managed entrance

The selected Python Runtime initializer checks the same entrance's actual
managed original before invoking its emitted Moon initializer. Missing,
partial or restored supply refuses without consuming the Runtime attempt.
Runtime current also retains that physical-current condition; a successful
initializer cannot detach from its original allocator lifetime. This private
check issues neither an initial platform original nor Worker capacity. The
unselected Runtime initializer retains its existing behavior.

The Python purpose uses a distinct opaque initial-platform original in the
existing Bootstrap Owner. It cannot consume or reinterpret the Native command
original. Its typed entrance reuses the same pinned MI217 physical mapping,
metadata registration, exclusive payload, default selection and partial-return
implementation. The selection reader must confirm the same actual interpreter,
process, original thread, component/recipe and initial generation before the
physical entrance observes allocator state. A later Host adopts that lifetime;
it does not issue another baseline or reservation.

Automatic allocator or Moon initialization must not precede this entrance. The
private Python runtime derivation changes only the exact pinned object's one MI
constructor registration into ordinary private data, preserving its instructions,
symbols, relocations and TLS. Its selected link must reject remaining static
initializers. The physical entrance also refuses an already initialized MI
object before mapping; an empty arena inventory alone cannot make it fresh.
The original command/toolchain object and explicit diagnostic interfaces retain
their existing initialization meaning.

The mapping and its metadata, alignment, options, default and partial state
remain with that original. Restoring the previous default does not retire the
mapping, registration, escaped allocations or process lifetime, and cannot fund
another Host. This mechanism supplies no loader/prelude coverage by itself.
Actual outside-arena initial services and their complete simultaneous envelope
must precede load; the interpreter input service, worker, VM and business
admissions remain separate. A type declaration or diagnostic finite selection
does not supply a missing ordinary operational original.

The private Python component's explicit entry captures its actual interpreter
and Python thread identities, original process/thread, and all three allocator
callback sets. It retains one static attempted/partial carrier before MI
mapping and registration. Its finite supplied initial-control facility has no
caller capacity arguments; exhaustion is not permission to grow or reissue it.
Normal current rechecks that same interpreter/thread generation, callbacks,
loader conditions and physical managed original. Foreign/copy/fork observations
cannot acquire or restore the original. Cleanup of the original partial attempt
does not depend on its failed normal-current view.

Only the explicitly selected Python producer variant compiles this entrance
and fences the Runtime initializer. It derives the exact pinned MI object,
requires a constructor-free link, and permits only its closed CPython imports
to resolve from the selected interpreter. Other unresolved imports remain link
errors. The source/recipe identities and original compiler inputs stay bound
to that component. Loading or compiling this variant does not cover the
preceding loader/prelude, complete outside-arena startup, or Worker/VM demand;
the ordinary factory still needs those separate actual suppliers.

Python binds this selected entrance through a separately generated closed ABI,
without requiring its symbols on the older diagnostic component. Its startup
caller retains the same interpreter preparation, library and persistent output
slot. All error/slot storage precedes acquisition. Reply loss never repeats
begin; only restoration of the published same original can be attempted.
Duplicate refusal grants no custody of the first receiver's original. A new
reentrant refusal cannot be masked by an outer success, including during
cleanup, while cleanup after an earlier failure remains available.

Retiring bounded startup-input DATA does not retire or recreate its interpreter
service. The Native caller retains that same service and its callbacks until
its own separate lifetime ends. Default restoration, input retirement and
mapping/module/process retirement have distinct meanings and carriers.

### Bounded private worker selections

The installed worker preparation ports accept exact path text, rather than
caller-provided Path or PathLike behavior. Each selected path has a nonempty
4096-character pre-copy ceiling and the existing 4096-byte filesystem-encoding
ceiling. Only admitted text is converted to an internal Path. The original
executable, link correspondence, file identity and digest checks still precede
spawn; accepting path text does not acquire a file or issue worker funding.

The selected environment has at most four entries, restricted to LANG, LC_ALL,
LC_CTYPE and TMPDIR without duplicates. Value length is checked before UTF-8
copying, followed by the existing 4096-byte limit. Invalid selections refuse
before consuming the slot or creating process descriptors. Missing original
funding continues to refuse before selection processing. These bounds constrain
startup DATA; they neither reserve interpreter heap nor acknowledge any process,
domain, descriptor or runtime retirement.

The private compiler transport projects the same domain's material before
process preparation. The original Native Owner then binds the live child
frame, channel and captured backing descriptor; the material alone cannot
launch it. After spawn and original-current confirmation, a single binding
byte releases the child to map that descriptor. A short or lost write is not
resent. The selected executable's byte check is correspondence, not funding
or code admission; the compiler producer must separately verify its original
source, configuration, module, toolchain and actual link inputs.

Compiler stdout is bounded control DATA, not a stop acknowledgment or an image
receipt. EOF is followed by original IPC restriction/return, typed stop and
physical region/descriptor retirement before parent arena cleanup. The caller's
backing FD and process-lifetime Runtime remain separately owned. Deadline,
partial response, failed spawn or uncertain cleanup retains the same parent
and process carrier; transport never substitutes PID absence, relaunches the
compiler, closes borrowed pipe FDs directly or manufactures a cleanup result.

After a failed invocation the maintainer caller may explicitly request cleanup
through that same registered process and parent. This is a separate bounded
cleanup window, not another compilation attempt. The existing Native child
receives at most one stop request per invocation of this cleanup routine;
request delivery alone cannot return backing. Only the same typed stop and
region/parent retirement chain precedes the original descriptor's one-shot
close. A lost stop/close response retains the original error and all partial
carriers. If process retirement completed but parent cleanup did not, the caller
continues that parent's cleanup without signaling or retiring the child again.
The primary compilation failure remains failed even after successful cleanup:
partial bytes/images are not accepted, and the final physical gate is unchanged.

The ordinary image producer can prepare that C executable independently of
executing it. This preparation uses the same exact original module receipt,
private two-library staging, binding/license/target checks and Engine Owner
configuration projection. The C API header closure is fixed to the selected
upstream/default-feature output, including its generated configuration; extra
headers, precompiled replacements and symlinks refuse. Compilation uses a
closed tool environment, records actual MD dependencies and original link
inputs, and checks the complete generated module ABI projection before linking.
No Config, Engine, native initializer or compiler child runs during this step.

The executable receipt remains correspondence DATA. Its caller must retain the
original prepared files and recheck the same module, recipe, toolchain, header,
object, executable and library bytes before execution through the original
funded parent. This preparation neither admits arbitrary user executables nor
supplies normal resources or the stronger same-module physical acceptance
required by the final producer and loader.

### Initial compiler domain in the original backing

Compiler preparation can select one initial execution-only domain from the
same Native parent. Before that domain's ordinary acquisition, the existing
Bootstrap Owner checks its original/current identity, the actual provider
control-byte observation and the matching charged control allocation. Only
when control is the sole existing allocation does it select capacity minus
that control as the accounting candidate. Earlier allocations, delegations or
domain attempts, including retired or partial ones, cannot become another
initial attempt.

This candidate is neither a physical maximum nor a claim that every byte is
usable for compiler buffers. The same allocator must acquire the extent;
fragmentation or other physical occupancy can still refuse it. Domain heap
metadata and fragmentation remain inside that gross extent. Its original
execution limit covers that extent, with zero retained bytes; this does not
fund a separate loader, Python runtime or VM domain. Non-byte limits remain
explicit source-bound inputs, and normal numerical funding stays unavailable.
The ordinary domain record is registered before physical acquisition, so a
partial mapping, loan or allocation remains with that same original pending
carrier. No failed attempt is retried as a new initial domain, and only the
existing original stop, borrower and physical cleanup boundaries retire it.

The maintainer compiler's source declaration may explicitly choose the closed
`initial_execution_domain` child selection with only work, attempts, holdings
and transfer limits. It contains no child byte estimate, retained reservation
or inferred execution budget. The assembly forwards that selection to the
same Native first-domain operation. Before process preparation it obtains a
fresh current projection from that original domain and forwards its original
retained/execution limits to the existing process Owner. The projection is
not cached as authority. Source/recipe disagreement refuses before registering
a process. The old explicit-size conformance declaration remains distinct and
unchanged; neither selection substitutes for a normal product supplier.


The ordinary maintainer `--compile` entry uses the original Native parent and
process path; it does not acquire an unbound holding or import Wasmtime into
the Python driver. It prepares the selected executable through the same
source/module/Engine/actual-link-input verifier, then creates one private
backing and passes that same original descriptor through the existing domain
and process Owners before the child can allocate Config or Engine resources.
The existing child helper retains one-shot start/IPC and typed stop/region
retirement. A closed compiler report is a compilation observation only: it
cannot acknowledge those operations or turn `RuntimeRetained` into an
allocation-level close. Parent descriptor close remains separate and sticky.

Image metadata is emitted only after both the original physical process path
and the source/module/library/program fences have completed. The returned
private result retains the parent control-runtime aliases for its process
lifetime; no Engine drop or parent arena close retires them. Failed or partial
acquisition, transport, descriptor close or final verification carries those
same originals and partial response without retry or fallback. The final
runtime producer still requires its stronger actual physical/workspace/Result
receipt for this exact module/source, not this compile-only receipt.


The source-bound maintainer selection keeps the existing 1-GiB compiler extent
and generation 1. It binds the selected original module, unchanged Engine body,
thread-custody Runtime and first-domain provider bytes. Its private parent has
finite work/attempt/holding/transfer ceilings 20/8/4/30; the single compiler
child uses 2/1/1/3. These bound this one compiler preparation, not business Run
permissions or a numerical product profile. Retained capacity is zero, the
original physical capacity funds the parent execution dimension, and the
Native first-domain operation derives the actual remaining payload after its
own control storage. No child byte ratio, second extent or implicit growth is
selected. The separate trusted control envelope remains explicit; this does
not assert that all Python/loader/OS allocations are paid from the arena.
The final producer and ordinary Local factory keep their existing physical
and normal-supplier refusals until those independent owners are complete.

### Ordinary Python Host resources

The ordinary Host follows the trusted platform boundary. Its public factory
loads the integrity-checked installed Core and actually acquires the selected
Config, Engine, Store, linear memory, File roots and durable byte Store. Missing
or inconsistent installed components still refuse; there is no raw-module,
Remote or diagnostic-resource fallback. Allocation failure is a real failure,
and partial acquisition retains the same cleanup carrier.

The existing Resource Ledger accounts for managed work, transfer/copy bytes,
retained bytes and concurrent holdings. Those limits are not a Native extent,
reserved CPython heap, worker delegation or hard RSS guarantee. Shared modules
and allocator caches remain platform-owned. Any selected native arena, worker
or zero-copy buffer still requires its actual original acquisition and release;
these ordinary limits cannot satisfy an imported-VM or worker-funding port.

The default logical Root permits 512 MiB of retained values and 576 MiB of
execution allowance. The existing Local Compute configuration quotes a
512 MiB execution ceiling and at least 200,000,000 retained bytes even for a
single Values task. The additional 64 MiB of execution allowance keeps Core,
transfer and setup reservations concurrent on that same Root. Transfer remains
bounded to 64 MiB, including the selected 12 MiB pool; planning work is one
million and attempts and holdings are each limited to 4096. These are finite
admission ceilings, not a reservation of platform memory or a guarantee that
every valid Program fits. Actual allocation failure and an insufficient Root
still refuse through their existing Owners, without replacing the Root,
discarding retained users or retrying an uncertain operation.

Normal initialization does not consume the private CPython initial-preparation
carrier or require an exact patch build, allocator callback census, prior
imports or a one-shot process history. That explicit private mechanism retains
its original lifetime for callers that selected it. The normal factory copies
the documented trusted state-directory option, including PathLike, once before
component acquisition and preserves its spelling and encoded path bound.
Reopen uses the existing durable installation validation, locks and saved Run
originals; it neither recreates missing authority nor retries uncertain work.

The ordinary image recipe explicitly selects `runtime_allocation: "platform"`
and the existing pinned Wasmtime dependency. Its provider fields are absent
originals, represented by null, rather than a fabricated Native holding or a
zero-capacity provider. Source/module/ABI, target, Engine settings, exact native
library and compiled-image hashes remain bound together. A mismatching image
is refused; it does not trigger JIT compilation or another runtime at load.

The selected platform pool has one function table with a finite 1808-element
ceiling, matching the packaged Core's declared minimum and maximum. This is
module-to-engine correspondence, not an ActQL language limit or additional
managed capacity. The compiler and artifact producer bind the exact recipe,
module and Engine identities before use. A changed table setting requires a
matching newly compiled image; an installed Host never resizes or substitutes
the selected pool to admit a different module.

The existing maintainer compiler may prepare that ordinary image using actual
platform Config/pool/Engine/Module handles. It closes those handles and does
not create a Wasm instance, business permission or worker funding. Packaging
binds the artifact digest into the matching SDK wheel and retains the declared
Wasmtime dependency. It does not ship an unused private runtime, import an
unused Host-capacity declaration or claim installed execution from compilation.
The original arena-backed recipe, private provider-link checks and strong
same-image physical verifier remain distinct and unchanged in meaning.

The ordinary factory supplies 128 transfer descriptors, counting both live
slots and concurrent borrowers. Setup, saved Run observations and the original
Result reader can coexist in that finite allowance; the transfer pool remains
12 MiB. This is a managed descriptor limit, not a byte reservation or an
all-history fit guarantee. Exhaustion refuses without replacing the pool or
discarding a borrower. Retirement still requires the original stop and cleanup
acknowledgments. Explicit diagnostic factory limits remain independent.

### Ordinary Host operation fuel

The ordinary installed factory uses a finite 1,000,000,000-instruction fuel
allowance for initialization and bootstrap together. Each subsequent admitted
outer Host operation has a finite 32,000,000,000-instruction allowance so that
bounded preparation, saved-original validation and admission share one budget.
Initialization does not receive a second budget
when the same factory begins bootstrap. These are runtime execution ceilings,
not capacity reservations, permission or a guarantee that every input fits.
The prior single 100M lifetime allowance does not cover ordinary initialization
of the complete packaged contracts. The raw diagnostic retains that original
lifetime policy; its evidence does not establish ordinary operation acceptance.

The serialized Host boundary installs fuel before new work only. Every private
ABI call, callback and nested phase shares that operation's remaining fuel.
Each already bounded Result delivery advance is an admitted phase: accepting
the previous chunk, checking current state and offering the next chunk share
one allowance. Backpressure does not keep an operation active between advances.
Run work, rows, calls, transfer, retained values and durable history remain
cumulative under their existing Owners; fresh instruction fuel resets none of
them. The Engine and compiled-image configuration still consumes fuel and its
identity is unchanged by this runtime policy.

An exhausted operation fails once and fences further normal Core work. It is
not refueled, retried, recreated or resent. Explicit same-original cleanup has
an independent finite 100,000,000-instruction allowance per outer close attempt.
Nested cleanup shares the current allowance, including when cleanup occurs
inside an active normal operation. Cleanup may only execute existing close
methods and cannot revive normal work, issue authority, acknowledge uncertain
COMMIT or infer release. Failed or pending cleanup retains its original handles
and carrier. A later explicit close attempt remains cleanup-only and preserves
all actual child, alias, FD, Store, Engine and parent acknowledgement boundaries.

Ordinary Result capture and commit preparation advance at most 256 existing
Owner work units per Host yield. The same current and authorization checks
still surround every advance, and the original cumulative work, workspace and
instruction ceilings remain in force. Batching reduces repeated transport and
current-check overhead; it neither refreshes fuel nor retries a failed phase.

### Bounded write-free reader groups

Write-free task preparation, task execution, Result preparation and publication
capture may drive their finite loops inside one original SQL reader. Each Python
Core method still checks physical current before and after its work. Task/Result
selection, chunk reservation and cleanup, publication retirement, File I/O and
Store writes remain separate boundaries; every returned loan is retained before
its enclosing reader can fail. The existing cumulative Owner work and instruction
budgets bound these loops. A task advance uses at most 256 original work units;
this changes no total allowance, waiting outcome or retry decision.

The standard owned SQLite connection records each executed transaction-control
statement, including cached statements and direct connection calls. Diagnostic
trace callbacks retain their normal behavior but cannot replace this internal
hook through the connection's trace setter. A write-free reader compares its
original connection, transaction epoch, schema and mutation count before and
after each step. Any change latches a refusal before the next step. Complete
adoption/settings membership established on entry is therefore reused only in
that same unchanged reader. Other physical adapters repeat their complete
inventory checks. No current permission or SQL row escapes as a reusable grant.
Longer DELETE-journal read locks last only for the existing bounded group; lock
contention never authorizes restarting or replaying an operation.

Once original installation files and the four metadata outputs are validated
through the same Host binding, the consumed bootstrap output and its input are
closed through their original Core loans before later Run transfers begin.
This returns only their transfer allowance. Saved files, metadata originals,
the Store, current fences and actual physical owners remain retained. A refused
close keeps the same partial installation and cannot trigger another bootstrap.

After a publication has been attempted, its Host-wide pending-write routing
pair blocks another write until the same original observation admits and
re-exports the complete stored index under the actual File, Store, current and
publisher checks. Only that transient routing pair is then retired. The
observation, original publisher, Core loans and per-publication attempted ticket
remain retained, so the original publication cannot be replayed. Unknown,
missing or refused index exports preserve the pending pair. The observation
action alone is neither acknowledgement nor a public RunState observation.

### Original observation data within one Host operation

The ordinary Host records a private monotone operation generation only after
entering its existing serialized operation. It is DATA, not a Run, continuation,
request identity, grant, instruction refill or authority decision. The generation
is cleared on exit. Raw diagnostic calls and every cleanup phase use the full
observation path. Nested cleanup neither mints a generation nor refreshes fuel.

The installed source/state file pair carries explicit provenance from its
original installation. One physical-current call may observe that closed pair
with one installation-root/raw-reader walk and both original pin/Store checks.
Every descriptor, filename and retained original is checked again on each call.
Custom root observers retain the sequential source/state path and original
callback order, even when the two callbacks are identical. This grouping neither
retires descriptors nor retains physical observations for another invocation.

The original binding may avoid rebinding the same input/current loans within
that operation only after a prior reader completed successfully. Each actual SQL
reader still checks the original file, settings, epoch and complete singleton
adoption inventory before and after its frame. The physical metadata import
accepts only that same original binding receiver, its currently verified reader,
its original retained input/current loans and the currently invoking instance.
Copied loans, changed operations, retired readers and failed frames cannot supply
this observation witness. Nonstandard private suppliers use the full old path.

The Wasm adapter retains only an alias of the first genuine immutable adoption
row already retained by Common. Within the same verified operation it can reuse
that DATA with fresh physical current checks on both sides. A different or zero
generation repeats the full singleton observation. Common still compares the
complete original Account bytes, adoption row and filesystem generation and
independently evaluates each protected operation. No Allow, permission, result or
mutable reader is cached. Original current/input retirement, cleanup
acknowledgments, failed COMMIT/Unknown and Store lifetime remain unchanged.
Private ABI83 adds the bounded i64 observation-generation import; installed
modules must match the existing exact generated ABI contract.

### Saved Run observations and Result reads

A saved payload response retains its same original Saved-read carrier. After
its payload, first workspace and clock have actually returned, response close
retires that carrier through its existing child-first cleanup, including the
original allocation-area descriptor. A pending return keeps the same response
and carrier; it does not repeat already acknowledged child closes or reacquire
an area. Cleanup association checks the same nominal carrier even when partial
construction has already entered closing; it does not require an active
permission or enable another read. Client close remains the owner of partial
acquisitions that never reached a response. No file, stored receipt, Run or reserved disk capacity is
deleted or replayed by this retirement.

The private saved-Result acquisition returns its already bounded and checked
metadata together with the same retained Core output. Its immediate caller
uses that original parsed DATA instead of reparsing the output inside another
current observation. This adds no cache, permission or lifetime token. Later
payload acquisition, physical reads, callbacks and delivery keep their existing
current checks and original failure/cleanup ownership.

A repeated submit first observes the authenticated original submission under
the same current Store snapshot. A ready record with the same intent returns
its existing admission without preparation, dispatch or a new executable Run.
A different retained intent returns the existing intent-conflict outcome;
lookup refusal cannot fall through to fresh preparation. This DATA response
does not supply the retained prepared input needed for executable restoration.

New ready admissions retain the original bounded task-material codec wire in
the same transaction as the Run, ready row and issuance counter. An optional
Run-row CID binds that exact wire. Up to three immutable UTF-8 chunks preserve
the existing 131072-byte physical row and 262144-byte logical material bounds;
complete inventory and selected-snapshot checks reject missing, extra, foreign
or changed chunks. Absent historical material is never regenerated or backfilled.

Executable restoration uses the existing canonical decoder against the saved
full Definition, invocation and authorization evidence. Its nominal saved
carrier binds the same retained prepared input, original authored intent and
document without ordinary submitted preparation or lowering. Original finite
and publication policies are restored separately. Existing current Activation,
control flags, Store binding and child-first retirement remain mandatory;
reference-only status and Result reads do not acquire that executable purpose.
Private ABI79 adds the two original restoration bindings and rejects older
installed modules through the existing exact export/ABI contract.

Cold status uses the existing reference-only submission projection and retains
its original saved snapshot until output cleanup. It returns only a saved SDK
state whose original observation key and public revision match the same Run.
It neither refreshes availability nor issues an observation clock or counter.
The existing validation export forwards both saved state and saved original
metadata projections to the same retained-lookup validator, alongside the
existing lookup and Result projections. Its private kind selection does not
replace original snapshot, current, configuration, full wire or output-lifetime
checks. Missing original snapshots still refuse before observation; no success
or live Run can be inferred from the projection kind alone.
Missing historical state remains unavailable, and refused validation retains
the same output/input loans. The live Run status/observation path stays separate.

A durable Client reference identifies saved originals, rather than a process-local
Run object. The original installation binding observes one current Store
snapshot. The legacy format retains its complete submitted-row inventory;
the indexed owned format uses the existing selected-original reader. Both
validate the saved observation originals, Run and submission identities, current
authorization, cancellation and original adoption scope before exposing attach
or lookup. Missing older observation originals remain unavailable; they are not
backfilled from a newly compiled Program, current defaults or another Run.

First acceptance supplies the same captured observation originals to both the
submitted-row Owner and the same-transaction Run inventory/CAS candidate. Their
complete initial row bodies must agree before any write. The optional original
is checked against the Run definition; legacy candidates keep their existing
bytes, and retained lookup does not backfill missing originals.

The SDK ready-row producer also projects the existing subordinate Run-reference
locator from the same admitted Submission reference, original Request and Run
Definition. Python saves its exact bounded key and reference wire with the Run,
ready row, issuance CAS and task-material chunks in that original transaction.
It neither derives a second identity nor interprets the locator as custody,
current authority, an admission, a completeness witness or COMMIT acknowledgement.
A locator insert conflict rolls back the same transaction; attempted-COMMIT
uncertainty retains the same original output and never repeats the write.

This retained DATA does not by itself select an indexed read or complete legacy
coverage. The actual original format-3 catalog and same-source mandatory atomic
writer supply that connection; an expired reference still selects its saved
original and never renews admission. A cold Run reference reads the exact tuple
locator, original Submission and linked Run, including their bounded task
materials and complete selected nested validator. Missing, ambiguous, corrupt or
foreign locators refuse; an indexed-read error never falls through to a scan,
fresh preparation, reissue or resend. Explicit unrelated integrity inspection
is separate from this selected read. The existing complete Python route remains
unchanged for legacy format 2 and private physical suppliers without the new
catalog port. Absent historical locators are not reconstructed on a read.
Native's explicitly indexed route and maintenance keep their separate profile.

A saved Result read validates the complete stored publication graph and the
selected manifest occurrence through the existing publication Owner. Its nominal
read source retains the exact finite policy and stored view. The shared SDK read
Owner still issues the read grant and observes delivery evidence under current
authorization; publication metadata alone is neither permission nor a physical
acknowledgment. Live publication preparation and writes cannot use this saved
source. Delivery-attempt lookup only observes the original attempt in the same
snapshot and creates no grant, payload Reader or first delivery.

The completed saved source may project only its already retained immutable
request and Run Definition into the existing exact-wire bounded row decoder.
Foreign or changed identity and the full nested row retain original admission.
During same-holder revalidation, its original typed Submission reference selects
fresh submitted and linked Run rows through the existing Common reader. Both
keys, revisions and bodies must match the retained originals. Current Run and
Result permissions, cancellation inspection, publication fences and physical
snapshot/cleanup duties remain; the reference is DATA, never an Allow or proof
of currentness. Initial and cold admission retain their complete path. Unrelated
historical payload integrity is a separate inspection rather than this selected
ordinary read's prerequisite.

Within that completed holder, the same original Snapshot can be reobserved as
immutable DATA when both fresh Submission and Run keys, revisions and complete
bodies are byte-exact. This preserves the original nested validator's result;
it does not assert that a different validator ran. The caller binds the actual
completed source identity, original admission relationship and fixed limits
before selecting this route. Missing or changed correspondence takes the full
existing selected-row reader, including all nested Policy, evidence and saved
state admission. Cancellation still runs before confirmed absence is returned,
and all current, publication-row and physical Reader fences remain independent.
Initial, incomplete and cold holders cannot select original-data reobservation.

The Host registers its operation carrier before acquiring children. It restores
the saved allocation directory and opens the committed generation in the
installation's Result Root with no-follow, identity, size and digest checks. It
neither creates a Writer nor finalizes an object again. Copied contract values
have ordinary runtime lifetimes; live descriptor loans, transfer outputs and
actual Store transactions retain their explicit original cleanup duties.
Partial preparation and failed returns preserve the same carrier for child-first
close, without reopening, re-reserving, replaying SQL or resending a submission.
These saved read operations do not supply unfinished status, wait or recovery
operations, and do not infer their success from an attached reference.

Within one saved payload observation, the original validator's typed binding
is consumed directly after the exact payload/allocation row fences. Reprojecting
that binding does not re-run the identical validator within the same call.
Nothing is cached across calls or snapshots: current authorization, original
parent identity, complete saved graph and physical row checks still run for each
observation. The finite operation ceiling bounds this work without promising
that every admitted input fits or refreshing any exhausted operation.

A trapped synchronous Wasm call can retain its in-call exclusion latch because
the ordinary return continuation did not execute. After that exact call has
unwound, the serialized Host may enter terminal saved-read cleanup with its
independent finite cleanup allowance. The private entrance spends normal Core
entry before retiring only the same saved parent's synchronous record/export
latches. It does not clear attempted operations, unknown transactions, delivery
state, physical stop/cleanup facts or buffer loans. Projection loans close before
their Store workspaces; every Reader, descriptor, input and parent still follows
its original child-first acknowledgment path. A live or reentrant invocation
cannot enter this cleanup path, and normal work never resumes from it.

The sealed Reader-facts path composes the two existing public Core validators:
original payload binding first, then the complete physical snapshot validator.
It does not implement either rule in Python or require a combined guest export.
Only success of both calls and the final original physical observation retains
same-owner immutable material. A failed enclosing current/physical observation
discards that material, retaining only the same cleanup loans. Successful binding
is recorded only after the whole original Store/current frame returns.

Only the existing bound Saved SDK byte callers consume that successful material.
Their public Source, Sealed record, selected binding, access and finish-current
checks remain mandatory, as do fresh descriptor observations and the complete
public Host current, Journal and transfer paths. Missing, changed, unbound or
live material takes complete validation; write/CAS/precommit paths keep their
full checks. This supplies no active custody transport or lifetime optimization,
capacity, permission, current-row proof or physical acknowledgment. ABI78 and
its full public Core validators remain unchanged; no private combined-export,
ABI82 behavior or runtime timing equivalence is implied.

### Accepted preparation failure

Local submission retains the unchecked original intent in `preparing` before
invoking its original parser and Checker. The preparation handle retains its
typed outcome separately from plan counts. A known preparation failure does not
turn a negative count, trap, failed current check or uncertain transaction into
a semantic refusal. It also cannot undo the earlier submission acceptance.

The same failed preparation and accepted intent select a bounded canonical
`preparation_failed` row candidate. The Host revalidates that original candidate
inside the existing fenced Store CAS, then independently reads the same
submission reference before returning `SubmissionPreparationFailed`. No Run or
dispatch is issued. COMMIT uncertainty preserves the original loans and remains
Unknown; this path never retries the write, parser or Checker. Repeated lookup
or submission of the same retained terminal observes that outcome rather than
preparing it again. A distinct submission continues through normal admission.

The optional physical problem fields are absent from older preparing/ready
rows, whose canonical bytes remain unchanged. Native readers retain the same
failure as terminal DATA and refuse fresh execution from that reference.

### Published Source preparation originals

An issued submitted preparation may retain the original published Source
computation beside its original submitted intent. Its environment retains the
same publication wire that was admitted with that environment. The existing
Source constructor selects Pure or Effect from the original authored program;
the Wasm preparation does not lower that program again or infer its kind from
counts. Access requires the same intent and environment originals and the
retained publication, rather than equal serialized substitutes.

For Pure, a checked view exposes the same existing prepared program and durable
document through the existing submitted-preparation carrier. Effect has no such
Pure view. Its graph supplies preparation counts only; those counts and the
ready outcome issue no Run, permission, physical target or executable restore.
The existing Run and material constructors must separately consume the original
Effect computation with their complete parent and lifetime checks.

The issued preparation retains a typed Source failure without reparsing on
subsequent observation. Failure projection reads that retained issue, while
changed original references refuse access. The preparation's existing input
borrow and environment dependency remain held until the same close operation
returns them. Source-free, structured-program and saved-material restoration
paths preserve their existing constructors and checks. This adds no Wasm
export, signature or ABI version; the changed implementation still requires a
genuinely matching module before a Host may consume it.

### Published Source request binding

A published Source's submitted carrier retains both the original input intent
and its exact prepared input. Existing Local Run constructors accept that
optional carrier only with the same prepared-input reference. They derive the
request through the existing canonical request function using the retained
intent CID. Omission preserves the legacy source-free input domain and all
existing request preimages. This carrier is not a new authorization or issuer.

The SDK caller uses that same request for lookup before Policy, compilation or
Run issuance, and forwards the same carrier into the existing Run constructor.
The Source/submitted views must retain the same original intent and checked
Pure program; equal replacement views refuse before that handoff. The existing
current, Account, submission, epoch and interruption checks remain in place.

For a saved SDK Run in this input domain, the original saved Submission and
canonical material decoder supply the retained submitted carrier. Restoration
recomputes only the request identity from those saved originals and compares
it with the retained request, complete expected Definition CID, context and
policy. It keeps the codec's original execution program and compilation; it
does not prepare authored input, issue a replacement Run or refresh authority.
Legacy saved requests retain their omitted-carrier path. This binding does not
make an Effect computation a Pure Run or enable physical work, approval or
continuation through an incomplete Effect Host.

### Adjacent payload preparation observations

After original read evidence and first delivery are durably acknowledged, the
normal live and Saved callers prepare the existing payload codecs and read the
same Core-issued Result/binding ordinals within one existing Store read frame.
The selected reader must remain the same nominal fact from that complete
inventory. No descriptor opens inside this fixed preparation, and neither a
write nor a read grant is combined with it.

The original frame still performs its complete File/current/Account and fact
checks around all three Core calls. Failure, changed originals or the final
physical fence returns no selected fact; the same original input/output loans
remain available for cleanup. No currentness or Allow result is cached. The
standalone codec and ordinal methods retain their original independent frames
for callers that deliberately select them separately. Payload binding and
physical snapshot validation continue through their two original Core methods.


### Original Source carrier during Run restoration

The original request input domain selects the retained submitted carrier for
both SDK and non-SDK restoration. A Source-bearing request must keep the same
carrier bound to its original prepared input, even when only the codec-bound
carrier remains and a live Source view is absent. Selecting an SDK profile is
not a prerequisite for preserving that request identity. The legacy source-free
input domain retains its existing absence of this optional carrier.

The actual restore caller passes this original unchanged to the existing
bounded materials restoration. That codec's compiled Owner, expected complete
Definition CID, current authorization, context and policy checks still apply.
Restoration neither prepares the submitted Source again nor issues another
request, Run, dispatch, lifetime or physical acknowledgment.

### Original platform Store and Memory

The ordinary platform runtime retains the same `LocalCore`, Wasmtime Store,
Instance, export table and Memory after instantiation and ABI validation. Its
private observation records those original objects, the original process and
Store context before fallible memory-type inspection. It does not select a
native holding or create another lifecycle Owner. The current Memory byte
length is observation DATA; neither its maximum nor a logical Resource limit
issues a Request allocation, parent admission or a physical-stop receipt.

Ordinary Core entry and return, bulk-copy entry and unsupported execution-child
callbacks check that same original. The callback also checks its real Caller
Store and exported Memory, with the original nonce as correlation only. Growth
of the same Memory is permitted within the existing selected bound; a cached
address is not used as a fixed arena. Replacing or losing the original during
an entered call refuses its return and preserves the existing closing fence.
Unsupported child imports continue to refuse rather than granting from this
observation. Complete Request constructor, input, output and failed-child
backing still belongs to its original Resource admission.

Core cleanup retains the same instance and observation if Store close fails.
Metadata is cleared only after that same Store closes successfully. A logical
pool close or a metadata observation is not the physical acknowledgement. The
existing native-holding observer and imported-child profile remain separate.

### Platform VM capacity and input-pool binding

Private scalar ABI 86 adds the fixed `platform_vm_observation` import and the
`open_platform` entry. The observation checks the same captured Store, Instance,
Memory and real Caller. Its state and immutable selected maximum are DATA;
ordinary initialization binds them to its existing Root and VM reservation
before opening the platform input pool. The public Client supplies neither this
port nor a callback, address, capacity original or allocation domain. Diagnostic
scalar opening and the existing original native/imported-child entrance remain
separate. An absent platform original refuses; it does not fall back to either.

The opaque `PlatformVMCapacity` is a view of that same Resource reservation,
not another allocator or lifecycle Owner. Equal limits on a different Root,
reservation or copied view do not match. Closing and lost observations fence
new claims on that original; a later observation does not clear the fence.
The non-Wasm fixed port remains unavailable.

#### Demand-sized working claims

`PlatformVMWorkingCapacity` is an original view of one shared allocation on
that same VM reservation. Its supplier must already back the entry/controller
prefix before calling the constructor. The retained and execution extents are
the complete simultaneous demand, not the unused policy ceilings. Growth checks
the same live VM original and the original Resource mutation fence, then updates
the same allocation atomically. A failed grow leaves its previous extents and
sibling/input allocations unchanged. Earlier retained and execution peaks stay
charged until cleanup; a smaller later quote does not release them.

Construction and exported-body users retain the existing `SharedBorrow` before
use. Closing forbids new growth and borrowers, but cannot release an allocation
with outstanding borrowers. Only their original after-use returns permit the
enclosing owner to finish cleanup of this suballocation. That operation does
not return the whole VM reservation or acknowledge physical Store destruction.
Other shared allocations retain their existing fixed-size behavior; only the
closed original VM working-claim implementation changes its own byte extent.

This view does not issue an imported child, a Request admission, a resource
policy, a read/send grant or a Run. The installing Host must connect its actual
original preparation admission, controller/constructor/output overlap and
failure retirement to these claims. Equal byte counts alone cannot replace that
connection. Node and mapped/native backing retain their own existing contracts.

#### Staged platform input construction

Platform input sealing owns its decoded input tree before a Request can borrow
it. The transfer's two wire copies alone do not cover that tree. The original
Buffer slot therefore retains a separate demand-sized working claim on the
same VM capacity. The existing Source preflight-control inventory and actual
wire length fund UTF-8 decoding and initial scalar preflight. The preflight's
observed node/depth geometry then selects the existing preserving-parser
construction inventory before grammar/tree allocation. Long scalar text is
not treated as one node per character, and the unused configured node/depth
limits are not allocated in advance.

The same Source cursor transfers once from preflight to grammar. The selected
data-key mode preserves original Unicode and keys; the default scalar, imported
and Native input paths keep their existing decoder. Original bounded polls
report their work on the same Root, without changing policy, engine, fuel or
VM geometry. This does not qualify the later Request/Plan work admission.

The Buffer slot retains its working claim and any failed/interrupted cursor
before those constructors can trap. A started failed parser is not replaced
by another seal on the same handle. Existing borrowers and the original input
cleanup must finish before the slot cuts its parser/tree aliases and returns
that suballocation. Returning a Buffer borrow does not itself retire the tree.
Parser capacity refusal, input error and physical cleanup pending keep their
existing distinct Host codes. Neither successful sealing nor cleanup grants
Source checking, Run execution or physical Store retirement.

#### Original Request admission and demand growth

The fixed platform preparation connection uses the existing backed region,
execution delegation, read use, live projection and `BackedPreparationAdmission`.
It does not create another admission framework or Root. Its caller already
funds the complete entry prefix, including region, origin, callback and receipt
controls. The region snapshots those original entry extents once. Only one
exclusive child can use this working claim; its extent describes current
allocation coordinates, not a mapped address or a promise to allocate policy
ceilings. Mapped and Native regions keep their existing fixed-window rules.

The existing delegation still reserves and reports the same nonbyte quotas on
the parent. Its existing logical byte projection avoids charging VM backing a
second time. Full child byte usage remains bounded and retained separately.
For a platform region, every canonical reservation or byte resize first claims
the entry prefix plus the child's complete retained/scratch coexistence from
the same VM. That fixed private Resource cut invokes no external callback
between validating demand and committing the ledger mutation. If physical
coexistence is insufficient, the old usage, serial and allocation remain
unchanged. Other imported origins have no platform binding and keep their
existing mutation path.

Reports cannot grow this claim or substitute for backing before construction.
Closing forbids new admission while existing covered disposal remains possible.
Original construction and body borrowers must retire before the child becomes
quiescent. The same enclosing owner then supplies its actual runtime/reader
retirement to the existing after-owner-ACK boundary, returns the read borrow,
settles the original delegation and closes its region. Only then can it finish
cleanup of the working suballocation. Neither logical quiescence nor a successful
report acknowledges physical Store destruction or returns the VM reservation.
The ordinary Host must retain this complete original chain before entering the
shared Request driver; numeric limits or a detached prepared value do not
replace that connection.

A platform input pool claims its actual mutable/immutable wire overlap from the
same existing VM capacity rather than reserving another whole execution pool.
Its separately supplied external-copy allowance remains separately charged on
the same Root. Pool limits are bounds, not allocations of their unused maximum.
The existing borrower, original stop, cleanup and shared-allocation release
sequence remains mandatory. Closing the pool settles only its own suballocations;
it does not return the VM reservation or retire the physical Store. The enclosing
Instance may mark that reservation closing for cleanup; the original Root/Store
retains its charge until existing physical retirement. The fixed memory maximum and
ordinary platform/no-native-provider profile are unchanged.

This connection does not by itself fund Request syntax, checking, compilation,
Plan, output, failed-child or retained Run overlap. Preparation input admission
checks the same original VM, but complete Request demand must still be claimed
before those constructors run. Neither this membership view nor remaining-byte
DATA supplies that missing Request admission. Source and component checks must
not be promoted to installed-image, durable approval, Saved or normal acceptance.
The diagnostic ABI cases use real Wasmtime VM/Root/buffers with explicit
physical-reader stop and cleanup ports; those ports are not a provider's live
reader or physical-stop proof.
