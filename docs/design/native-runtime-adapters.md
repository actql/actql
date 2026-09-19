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

Dynamic loading keeps the portable MoonBit packages and unrelated native tests
independent of a locally installed DuckDB library. A packaged native Host must
ship or require a compatible, verified DuckDB shared library as part of its
runtime bundle.

## Filesystem integration

The native filesystem adapter opens an explicit Store root as a directory file
descriptor. Object operations use validated relative names and remain beneath
that authority. Writers enforce their admitted byte limit before each write,
so a rejected append does not first allocate or write the excess payload.

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

The native Remote Site journal stores the portable dispatch-record body under
an attempt-occurrence key. A changed dispatch ID therefore cannot create a
second physical execution for the same language-task attempt. Admission and
each state transition install the canonical next body through SQLite before
the corresponding MoonBit transition commits. A lost response can reconcile
the identical installed body; a different body at that revision is a state
collision, not permission to overwrite or retry execution.

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

## HTTPS integration

The native HTTPS adapter uses the maintained libcurl easy API through a thin C
FFI. It loads an explicitly selected library from the admitted runtime bundle;
it does not implement TCP, TLS, certificate validation, or HTTP framing.
MoonBit validates the request shape and bounds, selects the operation, and
classifies the physical result. The adapter performs only the synchronous
physical exchange and reports its observed status, response bytes, or error.

The initial operation is a bounded JSON POST over HTTPS with mutual TLS. Peer
and hostname verification are mandatory, redirects are disabled, and the
protocol set is restricted to HTTPS. The response limit is checked before
each allocation or copy, so an oversized response is rejected without first
materializing it in full. Request bytes remain borrowed for the synchronous
call and response bytes cross the FFI once after the exchange completes.

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
- SQLite remains the first candidate for native durable journals. Its
  transaction and crash behavior must be verified by an integration slice
  before it is selected for the product journal.
- libcurl provides the native HTTPS and TLS implementation. The selected
  library, trust roots, and client credential paths are runtime-bundle inputs;
  their admission and grant scope remain common Host decisions.

Cryptography and any later storage or RPC dependencies should likewise use
maintained libraries behind thin physical adapters. ActQL-specific identities
and state transitions must remain independent of their transport encodings.
