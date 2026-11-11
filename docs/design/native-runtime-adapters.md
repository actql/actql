# Native runtime adapter boundary

## Purpose

The native runtime provides the same ActQL decisions as the JavaScript and
WebAssembly targets without requiring Node.js during startup, execution,
publication, delivery, or cleanup. Native adapters do not own language or Host
semantics. They perform physical operations selected and admitted by the
portable MoonBit control plane.

## Responsibility split

MoonBit owns:

- Connector capability and revision admission;
- exact task, attempt, material, and Site binding;
- query construction and result-shape requirements;
- capacity reservation and transfer charging decisions;
- completion, retry, reconciliation, retention, and reclamation progression;
- logical identity and publication contracts.

Native adapters own:

- loading an explicitly selected native library;
- opening, operating, stopping, and closing native resources;
- bounded exchange of physical batches and measurements;
- reporting physical errors and observed stop or cleanup facts.

An adapter may maintain physical state needed to operate a library. It must not
independently decide whether an ActQL attempt may be retried, completed, or
released.

## DuckDB integration

The native DuckDB adapter uses the official DuckDB C API through a thin
MoonBit C FFI. It does not invoke the DuckDB command-line program or a Node.js
subprocess. The generated C header is pinned with its upstream license under
`vendor/duckdb`.

The runtime library is loaded from an explicit path. The Host installation
must bind that path to the admitted runtime bundle and verify its revision and
integrity before the adapter can receive execution authority. Discovery of an
arbitrary library from a process search path is not an admission mechanism.

Opaque MoonBit handles own native resources. Database handles retain their
library handle, explicit close is idempotent, and automatic finalization is a
last-resort resource safeguard. ActQL settlement still requires an observed
operation outcome; garbage collection is not settlement evidence.

Result transport uses DuckDB's streaming prepared-result API. The adapter
checks the column ceiling before exposing metadata, fetches one native data
chunk at a time, and subdivides it under an admitted row and byte ceiling.
Metadata and each column-major physical batch are bounded before allocation in
the Host-facing buffer. Integers and decimals retain exact coefficients,
floating-point values retain their exact bits, and date or timestamp values
retain their physical ticks. These private physical frames still require the
Connector's MoonBit type matching, value admission, guards, and completion;
the C adapter cannot issue logical evidence. Prepared parameters use the same
Connector-owned physical projection as the Node Host and bind through the
typed DuckDB C API without SQL interpolation. The native acquisition runner
executes catalog validation, complete input validation, and the selected query
inside one DuckDB transaction, then ends source access before asking the
portable Host to commit its two-receipt observation.

The native fixed-Compute runner consumes the exact candidate selected by the
portable DuckDB driver. It bounds every input shape and compiles bounded batch
inserts before starting the transaction, binds only Connector-admitted typed
parameters, and streams physical result chunks into the existing portable
Compute receiver. A committed DuckDB transaction is recorded as physical
settlement, but only the exact portable attempt verifier can create common
completion. A precommit failure rolls back and preserves the rollback outcome
separately from the primary failure. The standard dispatcher path registers
the exact common task before native I/O, closes the physical database before
settlement, and reaches DAG completion only through the common lifecycle.
Retained output storage and Node-free Local execution remain later migration
steps.

Dynamic loading keeps the portable MoonBit packages and unrelated native tests
independent of a locally installed DuckDB library. A packaged native Host must
ship or require a compatible, verified DuckDB shared library as part of its
runtime bundle.

## Filesystem integration

The native filesystem adapter opens an explicit Store root as a directory file
descriptor. Object operations use validated relative names and remain beneath
that authority. Writers enforce their admitted byte limit before each write,
so a rejected append does not first allocate or write the excess payload.
Store owners that perform crash recovery also hold a named nonblocking OS lock
for the lifetime of the Store. Lock files remain stable namespace entries; the
lock is the open descriptor, and releasing it does not use unlink as an
ownership signal.

Sealing synchronizes the staging file, captures its exact device, inode, and
size, creates the final name without overwriting an existing object, removes
the staging name, synchronizes the Store directory, and rechecks the committed
generation. A failed synchronization or cleanup retains enough physical state
for the same operation to retry without rewriting the payload. Replacement of
an owned generation is rejected rather than unlinked.

Readers open the exact committed device, inode, and size without following a
symbolic link. They return bounded byte chunks and require the caller to reach
the expected length before a final descriptor check can succeed. The open
descriptor pins the physical generation even if its directory name changes.
The portable caller still verifies the expected payload digest while
streaming; device, inode, and size are not a logical identity or a substitute
for content integrity.

These calls report physical observations only. MoonBit control code owns the
reservation, publication, retry, completion, and reclamation decisions. A C
finalizer is only a best-effort safeguard for abandoned uncommitted resources;
it is not settlement or durable cleanup evidence, and it does not remove a
successfully sealed object.

Formal publication persists the canonical Result schema and every admitted
Run-bound contract before installing the single scoped public-index row. The
index row is the visibility boundary. Restart retrieval re-admits the stored
contract bodies and revalidates the schema wire against its declared CID; it
does not depend on a process-local schema copy retained by the caller.
Committed Result resolution loads every binding named by the index and asks
the portable publication owner to select the exact Result occurrence. The
filesystem adapter does not infer a binding from a material name or path.
Trusted clock observations use SQLite compare-and-swap to preserve a monotonic
lower bound per admitted clock contract. A process restart, concurrent reader,
or wall-clock regression cannot extend a Result's retention interval.

The standard native publication service accepts the complete checked
Effect-free Run evidence plus an immutable publication intent. It issues the
publication request, attempt, and public-index contracts through the portable
owner rather than accepting environment-authored contracts. Before creating
an occurrence it checks Host authority before resolving the one scoped
committed index, then rechecks authority against the candidate index before
commit. Denial therefore reveals neither publication existence nor a retained
index identity. An exact retry, concurrent winner, or restart-visible commit
is re-admitted and validated against the complete chain; a changed policy or
target is a conflict. The single Store index insertion remains the durable
visibility boundary.

The standard native Result-access service follows the portable access
progression: request authorization, committed Result resolution, initial
availability, read admission, grant issuance, and delivery. Every byte read
and the terminal receipt boundary recheck current authority, the durable clock
lower bound, retention, and grant expiry. The service returns an explicit
session so failed sinks can record a confirmed prefix or retain cleanup
responsibility instead of losing an active reader behind a convenience API.

The Native relation-file reader consumes Query and whole-input reads issued by
one installed managed Plan. Query capture borrows the Plan's retained original
acquisition, declaration and selected provider; an equal provider quote cannot
replace that original. File listings retain their original ResourceRef issuer
and monotonic clock. Both routes use the same Native capture holder, physical
Ledger and child-first cleanup; neither route creates an auxiliary Run or Ledger.

The Native whole-input command keeps its original Request compilation, Whole
Plan, captured module and adopted Run. Its entry borrows the preparation's
existing reservation; it neither allocates a second capacity token nor coerces
the Program into a Query/source-free purpose. Logical Work cleanup drops the
borrowed prepared binding before the original execution returns its physical
context. Only that original parent can acknowledge/report physical retirement.

A Whole input executes through the retained Plan's same configured DAG and
existing retained Local task loop. Its original root still performs every
authored operation, and dependent tasks consume its original managed output.
The Source-free task entry retains its zero-Source
predicate; a supplied input is not relabeled to satisfy that predicate. The
Whole projection checks the original Plan/Prepared/Request/DAG binding before
entering execution and refuses copied or unbound Runs without observing a
replacement current callback.

Source publication identifies the complete captured input using its retained
acquisition bounds, independently of a narrower aggregate Result. The original
input CID and effective publication policy travel with the same sealed
invocation; the caller does not parse their evidence wires again. Incremental
identity/metadata construction grows the same preparation reservation before
each constructor while its actual Source/output children coexist. The caller
uses the Core scanner's shared structural workspace count: its three writers
and actual input-column metadata coexist with the existing bounded traversal
frames. The value-node admission maximum is not this combined slot count.
This immutable quote grants no capacity and changes no input or wire limit;
the original per-transition construction quote still precedes physical growth.
Publication then uses the original captured Result pin and the existing
Journal/Store/Saved continuation, preserving partial generations and ambiguous
commits.

The accounted listing constructor retains the acquisition's original
configuration in its existing report holder before a response borrow can match
the derived listing configuration. Row owns the additional H1/R2/W1 tariff in
both its planner projection and actual reservation. This is one reference and
its Some carrier, not copied Catalog/schema data. Only confirmed Row cleanup
severs it together with report/scan backing. It supplies no read permission or
completion evidence.

## SQLite integration

The native SQLite adapter is the first integration slice for a Node-free local
journal. It loads an explicitly selected SQLite 3.37 or later shared library
and uses the published C API. Native builds require the corresponding SQLite
development header; product packaging must bind the selected library and
header ABI to the admitted runtime bundle.

The adapter creates a strict, versioned record table in WAL mode with full
synchronization. Inserts are absent-only. Updates use a revision predicate in
the SQLite statement, so two processes cannot both commit from one observed
revision. Reopening the database recovers the committed revision and exact
body. The durability claim remains limited to SQLite and the selected
filesystem profile; it is not a claim against loss of the storage device.

SQLite owns the physical transaction and locking state only. MoonBit creates
the canonical record body, chooses the expected revision, and decides what a
successful compare-and-exchange means for dispatch, publication, cleanup, or
any other application state. The adapter cannot turn a row update into an
ActQL completion.

The `actql-native-runtime-bundle` executable is the standard Node-free update
surface for the native runtime bundle Store. Its `install` operation reads an
exact source generation and copies it through 64 KiB chunks into the Store's
bounded installer. `activate`, `drain`, `rollback`, `retain`, `release`,
`reclaim`, `verify`, `inspect`, `recover`, and capacity inspection call the
same MoonBit lifecycle owner used by product dispatch. A failed operation does
not invent a cleanup decision in the command layer: installer cancellation and
Store close report unresolved durable responsibility as cleanup pending.

The bundle catalog distinguishes a reserved install intent, ownership obtained
by successful exclusive creation, and the exact sealed generation. Recovery
may delete only a name whose device and inode match the recorded ownership; it
does not derive deletion authority from a new directory observation. A crash
between creation and the durable ownership record leaves a quarantined intent
rather than authorizing deletion of an unknown file. Removal also retains the
catalog reservation until directory synchronization succeeds, including when
retry observes that a prior unlink already removed the name.

The command receives library paths, target scope, authority material, and
capacity limits explicitly. The required `--trust-config-name` selects one
versioned trust configuration below `--authority-root`. It may name multiple
public keys and independently mark each key as eligible for new bundle
admission. A normally rotated key can therefore remain available to verify
records already accepted into the durable catalog without authorizing another
install or adoption. Omitting the key removes historical verification too;
that is a stronger trust revocation and can make the Store intentionally
unopenable until an operator supplies the required audit key. A single-key
installation uses the same configuration with one authority and an explicit
`admit_new_bundles` value. The retired `--issuer-authority`, `--key-id`, and
`--public-key-name` options are rejected by argument parsing before a Store is
opened; no default admission policy is synthesized from them.

The trust configuration has version
`actql-native-runtime-bundle-trust/0.1` and contains a bounded `authorities`
array. Each closed entry contains `issuer_authority`, `key_id`,
`public_key_name`, and `admit_new_bundles`. The install command separately
requires `--signature-key-id` to name the signature key in the signed envelope.
It does not infer that key from the trust configuration or another option.
Duplicate authority/key pairs, unknown fields, unbounded inputs, and a signature
from a verification-only key are rejected before component output is created.

This explicit input makes the selected deployment dependencies observable and
prevents a hidden Node fallback. Public-key, trust, manifest, and signature
inputs are bounded before allocation; component bytes are never assembled into
one command-layer buffer.

The native Remote Site journal stores the portable dispatch-record body under
an attempt-occurrence key. A changed dispatch ID therefore cannot create a
second physical execution for the same language-task attempt. Admission and
each state transition install the canonical next body through SQLite before
the corresponding MoonBit transition commits. A lost response can reconcile
the identical installed body; a different body at that revision is a state
collision, not permission to overwrite or retry execution.

Every admission or transition that exercises current execution or evidence
authority reads the exact durable Site binding in the same immediate SQLite
transaction as its record mutation. Restart takes that transaction before it
recovers the dispatch set, fences every nonterminal record, and advances the
binding. An already open handle for the prior generation can still query
historical records and commit cleanup-only transitions, but it cannot admit
new execution or advance execution or evidence state.

Restart recovery scans one record at a time in stable binary key order. The
physical adapter returns only the stored key, revision, and bounded body.
MoonBit re-admits the canonical record, verifies that its attempt occurrence
derives the stored key, checks the revision, and restores the common state.
An alias key or malformed body stops recovery instead of acquiring execution
or cleanup authority.

The native Coordinator journal uses the same transaction substrate but a
separate namespace and common Coordinator state machine. Its durable MoonBit
record carries canonical dispatch intent plus any admitted evidence, subject,
and measurement bodies needed after restart. Physical SQLite rows therefore
cannot manufacture evidence from CID strings or turn transport uncertainty
into a Site observation.

The native publication payload Store also uses this transaction substrate.
Its portable MoonBit request binds the Store authority, publication attempt,
material generation, Result definition, logical relation, schema, ordering
evidence, durable codec, row count, and admitted byte limit. The lifecycle
separates intent, capacity reservation, physical writing, sealing,
reclamation, and confirmed release. SQLite compare-and-exchange makes each
transition durable before the portable state commits.

One Store root has one deterministic SQLite journal, so opening the same root
from multiple processes cannot split its byte or object authority. Capacity is
reserved before a physical writer is created and is released only after the
exact owned generation is reclaimed. Sealed payloads survive process restart;
recovery verifies their exact generation and reclaims unfinished payloads one
record at a time. If unlink succeeds but directory synchronization fails, a
retry synchronizes the directory even after the name has disappeared;
capacity is not released until that confirmation succeeds. The physical
digest is checked while a bounded reader emits the stored bytes. It remains
distinct from the logical relation CID and from any delivery-format digest.

Native delivery composes that verified reader with the portable durable-row
framer and canonical JSON, JSONL, and CSV serializers. Input chunks, row
frames, and caller-visible output chunks are independently bounded. The
delivery digest covers the exact emitted format bytes and is not reused as the
payload digest or logical CID. An empty JSONL delivery still produces an
explicit terminal observation before its zero-byte digest can be finalized.
Failure before terminal delivery keeps the payload reader pinned until the
caller closes it or a later cleanup owner confirms release.

The formal native delivery path additionally verifies that the committed
Manifest, read grant, retention policy, durable Result binding, and exact
payload generation describe the same Result occurrence. Its immutable attempt
and initial streaming record are durable before a byte is exposed. Store reads
and sink confirmation are separate: at most one bounded chunk is outstanding,
only its sink-confirmed prefix advances delivery accounting, and even an empty
delivery requires an explicit successful sink-end observation. A successful
end issues the canonical delivery receipt and terminal record before it is
reported. A failed or cancelled end records the confirmed prefix and exposure
state without converting an unconfirmed suffix into success.

Each read-grant use is claimed by exact delivery-attempt CID in one canonical
SQLite record. Compare-and-exchange serializes concurrent claims, an exact
attempt retry consumes no additional use, and a different attempt is rejected
before opening the payload when the durable `max_uses` limit is exhausted. A
claimed use is not refunded merely because the process stops before delivery.

Formal publication validates the complete Run-bound chain, including every
Result derivation, ordering proof, retention policy, and durable binding,
before persisting its semantic contracts. The public index is then installed
as one absent-only SQLite row keyed by namespace, authority scope, and exact Run
Definition. That row is the visibility boundary. An exact retry returns the
same commit, while a different Invocation, attempt, Manifest, or intent for
the same scoped Run is a conflict. Restart lookup re-admits the exact stored
index, and formal delivery refuses an index that has not crossed this durable
commit boundary.

Delivery contracts and the latest append-only record head are stored in the
same SQLite authority and can be re-admitted after process restart. A terminal
success remains an auditable historical fact after its payload is reclaimed;
current material availability is checked separately. This native Store layer
does not itself grant caller authorization or decide dynamic revocation. The
standard Host must perform those checks before each physical use and before
accepting the terminal receipt.

## HTTPS integration

The native HTTPS adapter uses the maintained libcurl easy API through a thin C
FFI. It loads an explicitly selected library from the admitted runtime bundle;
it does not implement TCP, TLS, certificate validation, or HTTP framing.
MoonBit validates the request shape and bounds, selects the operation, and
classifies the physical result. The adapter performs only the synchronous
physical exchange and reports its observed status, response bytes, or error.

The adapter supports the existing bounded JSON control POST and a bounded
GET, POST, or PUT exchange over HTTPS with mutual TLS. The generic exchange
accepts a strictly bounded set of validated headers. It is a physical
operation for one control body or one admitted data chunk; it is not an
unbounded whole-result transport and does not decide Transfer retry, commit,
or cleanup state. Peer and hostname verification are mandatory, redirects are
disabled, and the protocol set is restricted to HTTPS. The response limit is
checked before each allocation or copy, so an oversized response is rejected
without first materializing it in full. Request bytes remain borrowed for the
synchronous call and response bytes cross the FFI once after the exchange
completes.

Cancellation is checked before the request and through libcurl's transfer
progress callback. The current MoonBit call is synchronous; a caller that must
cancel an in-flight exchange from another execution context needs the later
operation-handle integration. A timeout or transport return is not proof that
an independently executing remote operation stopped. Common dispatch,
settlement, reconciliation, and cleanup decisions remain in MoonBit.

The integration fixture creates independent test authorities, requires a real
client certificate, rejects a certificate from the foreign authority, tests a
disconnected exchange, and enforces the response bound. Node.js is used only
to host the test HTTPS endpoint. It is not spawned or linked by the native
adapter or its product runtime.

The native Remote Site client composes this physical exchange with the native
Coordinator journal. A dispatch intent is durable before its first send.
Query and cancellation require that exact existing intent and cannot create
execution authority. Responses pass through the portable MoonBit envelope,
state, dispatch-binding, and evidence admission before the resulting
Coordinator observation is installed. A transport failure, non-success HTTP
status, malformed response, or foreign binding first advances the durable
intent to outcome-unknown. Failure to persist that uncertainty is reported as
a compound error rather than hiding either fact.

The current operation is synchronous and accepts an already admitted endpoint
URL. Endpoint discovery, reachability comparison, and authorization remain
Host planning responsibilities. The client does not retry, select another
Site, infer native stop from HTTP cancellation, or turn a response into common
task completion.

The native credential resource service composes the portable credential grant
and use contracts with a durable SQLite ordinal claim before external I/O. An
exact use retry never issues a second request, a process restart does not reset
the use ceiling, and an expired or foreign scope is rejected before consuming
a claim. The physical HTTPS adapter reads one exact owner-only secret file,
checks its generation and contents across the read, applies the bearer header
internally, and keeps redirects disabled. Secret bytes never cross into
MoonBit or Connector code. The configured operation fixes the exact origin and
path; a grant does not expose a generic authenticated HTTP client.

An outbound-only native Site uses the same HTTPS adapter to poll an admitted
Coordinator endpoint. The poll envelope carries the exact canonical dispatch
request and its CID, but grants no execution authority by itself. MoonBit
re-admits the request and checks the Site generation, task attempt, grants,
budget, obligations, and runtime pins. The Site installs the accepted record
in its durable SQLite journal before posting an acknowledgement. Repeated
delivery reconciles that same record instead of starting another execution.

The poll and acknowledgement calls deliberately contain no automatic retry or
re-execution policy. A missing acknowledgement leaves the Coordinator and
Site journals to reconcile their independently durable facts. The current
slice also carries an explicit release operation. Release advances only the
exact accepted dispatch owner through the portable cleanup plan, posts the
durable Site observation, and makes an exact retry observe the same released
record rather than reclaiming twice. It proves outbound authenticated
admission and release without requiring a native listener; it does not yet
claim a complete remote compute, bulk transfer, or Coordinator gateway
implementation.

## Supported native profiles

The initial native product profiles are:

- macOS on arm64; and
- Linux on x86-64.

Both profiles use the same MoonBit control logic. Platform-specific code is
limited to physical adapter operations. A target is not supported merely
because portable packages compile for it; the standard execution,
publication, restart retrieval, delivery, and cleanup paths must pass on that
target without spawning Node.js.

Additional operating systems require a physical loader, filesystem durability,
and native dependency packaging implementation with the same contract. They do
not require a second Host state machine.

## Data boundary

The scalar query entry point is only the native library integration slice. The
standard execution path must use bounded batch or column transfer and must not
turn the FFI into a per-cell application ABI. Physical result integrity and
logical relation identity remain separate obligations.

The native adapter must reject unsupported physical types or result shapes
before common completion. It must not repair values, reorder rows, or infer a
logical identity from a physical digest.

## Selected dependencies

- MoonBit native FFI and C stubs provide the language boundary.
- The DuckDB C API provides database execution.
- Operating-system filesystem primitives provide the local durable Store
  adapter, with durability claims limited to the selected filesystem profile.
- SQLite provides native durable journals and shared local capacity
  reservations. Its selected synchronization and filesystem profile bounds
  the durability claim.
- libcurl provides the native HTTPS and TLS implementation. The selected
  library, trust roots, and client credential paths are runtime-bundle inputs;
  their admission and grant scope remain common Host decisions.

Cryptography and any later storage or RPC dependencies should likewise use
maintained libraries behind thin physical adapters. ActQL-specific identities
and state transitions must remain independent of their transport encodings.


The existing Native Signature Library has an explicit cleanup-only close.
Requesting it stops new cryptographic work through every alias of that Library;
its original dynamic handle remains retained while any original SHA-256 EVP
context is live. Each context has its own explicit close acknowledgement, and
successful digest completion also retires its context. The Library closes only
after those physical contexts retire. Escaped inert managed references,
application material and Host/domain retirement remain separate obligations.
An unconfirmed dynamic close is sticky and cannot authorize an automatic retry,
replacement load or release acknowledgement. Finalizers are best effort and do
not supply either explicit acknowledgement. A lost unfinished context leaves
its retained parent Library cleanup pending even if a finalizer frees native
memory; only the original explicit context operation can acknowledge it. Existing loading selection,
credential authority and numerical resource admission are unchanged.


### Streaming digest of an original file Reader

Packaged runtime members use the shared incremental SHA256 implementation
rather than a digest selected by the operating system. The caller feeds at
most 64 KiB per `Reader.next` call;
the Hasher retains only its fixed digest state, block and word schedule, not
the input. Digest-only members are never collected into a whole-file buffer.
Metadata collection retains its separate admitted 64 KiB bound.

Hashing does not reopen a path or select an OS-specific digest implementation.
The same original Reader remains open through EOF and opened-file identity
inspection, followed by the existing `finish` acknowledgement. Physical read
or currentness errors retain that Reader for original cleanup; digest failures
do not choose another implementation. Final digest comparison and the original
observation's currentness check still precede witness issuance. This does not
change permission, storage identity, resource admission or cleanup credit.

This consolidation does not broaden native Host or bootstrap platform support.

### Original file replacement observation

The Native row-file child retains the original Writer replacement acknowledgment
instead of discarding its returned generation. Its opaque immutable observation
binds the selected file and row, checked expected version and changes, exact
submitted replacement bytes, and the returned device/inode/size generation.
The existing filesystem owner returns this observation only after its staging
and directory synchronization and generation confirmation succeed. Attempted
replacement, submitted bytes, a later read or successful cleanup cannot create
it. A post-rename synchronization error retains uncertainty without a retry.

The original update quote includes the returned generation, observation and
optional holder beside the existing replacement buffer. The shared child census
includes its retained slot. A receiving Host must retain the same observation
on its own backing before child retirement; closing the child only severs that
child's alias. Historical replacement evidence is separate from current write
permission, a Journal receipt commit, Result publication and physical cleanup.
