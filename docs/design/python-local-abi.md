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

An allocation is retired before cleanup. Readers must acknowledge physical stop
before their exact borrow is returned. Failed stop or cleanup retains the same
handle and allocation for retry. The root reservation is settled only after all
allocations are released. Closing a pool blocks further admission immediately.

## Instance-private Wasm facade

The physical adapter installs one fresh positive instance nonce. It supplies
positive physical input identifiers that cannot be reused while live. Core
issues monotonically increasing handles from a shared sequence for input and
reader kinds. Handles are never serialized Client references, durable operation
identities or execution authority. The adapter must keep handles private to the
owning instance; neither a handle nor a nonce is an authorization token.

The Python physical bridge checks the installed artifact digest, scalar ABI
version, exact callback signatures, required exports and linear-memory maximum
before opening the instance. `actql_host_abi_version` returns 6; this private ABI
version is independent of Client wire and package release versions. Optional
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

## Physical DuckDB boundary

The private Python adapter loads an explicitly installed standalone DuckDB C
library with a verified digest and selected version. It neither discovers a
Node package at runtime nor falls back to the Python extension's unbounded
row-fetch APIs. The existing native adapter's C layouts and scalar row/field
codec are shared boundary references. Canonical environment settings are
generated from `adapters/connectors/duckdb/environment-contract.json`.

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
it can resume the original Run. Earlier ABI modules are refused by the ABI 4 bridge;
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

The private ABI 4 `actql_program_install_source_environment` takes one
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
