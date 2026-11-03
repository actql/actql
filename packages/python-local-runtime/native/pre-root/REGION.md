# Same-provider physical extent transport

`owned_region.inc` is included once by the existing `owned_capacity.c` provider.
Its private ports prepare FD-backed storage and relative extent transport. They
do not issue a SharedCapacity, child delegation, Run admission, worker startup,
VM capacity or Source/Model/publication permission. Ordinary Local installation
continues to refuse without complete original pre-spawn funding.

The trusted installed supplier lends an exclusively initialized, exact-sized,
private regular FD. Acquisition checks its physical identity and refuses an
already initialized original; it never resets a saved region after parent death.
The original mapping contains the same provider's control records and extent
table. The supplier remains responsible for the FD and its one-shot close.
Acquisition does not create, duplicate or close an FD. Failure after mapping
leaves the original mapping in the output carrier for cleanup.

Only the original, current, transferred physical lease can lend an exact live
extent. A parent-local, address-bound loan prevents original extent retirement.
Equal or copied loan fields do not allow projection or return. A writable loan
is exclusive; read-only loans may coexist, and exclude a writer. The portable
Owner must additionally bind these physical facts to the original Ledger,
SharedCapacity, Allocation/Borrow, child identity and extent and budget concurrent
children. These C exclusions are physical guards, not that nominal accounting.

`lend_extent_range` projects a page-aligned subrange of that same allocation.
External physical uses are recorded on each page: disjoint writers can coexist,
overlapping readers can share, and any overlapping writer is refused before any
page's counter changes. The entire parent allocation remains unretirable until
all page borrows return. The supplier must match the Core-issued relative extent
to these exact physical bytes; it cannot round a smaller logical grant into a
larger shared mapping. No sub-page writer is silently widened to a page.

A transport reference contains device/inode, generation/recipe, original
capacity, page-relative offset/length and access mode. It contains no process
pointer. A trusted child supplier must validate its nominal original child,
borrow and currentness before using it. A copied reference or matching FD is not
an authorization. The physical mapping checks the same FD identity/layout and
maps only that extent, without mapping or acquiring the parent's allocator lock.
The view exposes shared backing bytes at a different local address. It supplies
no child allocator or permission to treat the whole region as VM funding.

View storage, local VM mappings, FD/control carriers, process/VM/loader and
independent Store overhead need separate funding. The shared pages are the same
original backing, not a second execution-byte allocation. Parent-local allocator
metadata has one writer. The child never writes it or leaves its lock stranded.
Parent pointers, loan/view carriers and Common nominal tokens are never sent as
wire data. There is no additional allocator provider, Ledger or cleanup queue.

`close_extent_view` acknowledges only the local unmap. A failed unmap retains the
same view; retry uses the same address and length. Successful double close issues
no second unmap. It never returns the parent loan. Only the existing Owner's
same-child confirmed-stop and physical cleanup path may call `return_extent`,
then return the original Common borrow. Cancellation, response loss, parent death,
an empty quota or another process's success cannot supply that acknowledgement.
If the parent is gone, the durable original custody remains unresolved; this
preparation does not provide a reconstruction supplier or restart the worker.

The Native provider and worker caller do not yet consume A's portable backed
delegation type through these ports. Worker transport, durable parent-death
custody, complete pre-spawn funding, Wasmtime, runtime recipe adoption, wheels and
public installed E2E remain unverified. `fixtures/region.c` tests physical guards
and shared bytes using the original 64-page fixture, with no worker/VM startup.

## Linux x64 process profile

The default `platform_native/host_bootstrap` C entry selects the process-only
provider for its actual Linux x64 compiler target. Its existing Moon native
compiler flags select GNU feature visibility before system headers, and its
link flags retain pthread support. Imported and scoped-read providers keep
their separate source selection. Compiling `owned_capacity.c` alone without an
explicit profile still refuses Linux x64.

`owned_linux_x64_process_profile.h` requires Linux x64/glibc, little-endian LP64,
64-bit pointers, ranges and FD offsets, 32-bit PID records, and always-lock-free
shared PID atomics. It reuses the same allocator, FD mapping, address-bound
loan/view, current scope, thread and child-first retirement implementations.
Control sizes and page geometry come from that compiled provider; an ARM or
Darwin layout is not a substitute. This selection does not issue Core funding,
authorize a read, acknowledge a child stop, or select an image, Rust or Engine
profile. The existing original child/borrow/current and retirement duties remain.

`linux-x64-process-source.json` binds the selected source and pinned toolchain.
`python3 scripts/test_native_linux_x64_owned_process.py` requires an actual
Linux x64 host and retains the original physical-case binaries and controls.
Its C results do not qualify Moon FFI or a normal installation. The existing
Native HTTP and separated-network wrappers must still execute all their
selected packages and later controls; this profile provides no case exclusion
or fallback. Source selection alone is not execution or distribution evidence.

## Original child allocation domain

The trusted child supplier can bind the original Core payload to an
ExclusiveWrite view and suballocate its local physical control table inside
that same payload. This reuses the one provider's allocator, protection, TLS
and retirement functions. It performs no second mmap/reserve, creates no
Ledger/Root, and cannot fund unrelated process/VM/FD/control overhead. The
control bytes reduce the available original payload; no allowance is extended.

A copied, readonly, unconfirmed or unbound view cannot acquire this domain.
The address-bound view consumes this port once; initialized/dead-child payload
control is never reset. The shared control header contains no process pointer.
The caller-funded view holds its in-process identity and original physical
loan separately. Independent simultaneous children keep disjoint writer ranges.

Domain retirement requires all original allocations/scopes retired and leaves
the outer mapping held. Ordinary whole-mapping close refuses an interior domain.
View close refuses a live domain, and parent loan return still requires the
existing Owner's scoped child-stop plus view/FD-borrower retirement facts. Lost
responses or parent death do not create those acknowledgements or new credits.

This source/private fixture is not adopted numerical funding, a compiled
Wasmtime runtime, worker dispatch or installed Python product acceptance.

## Backing-extent work observations

`actql_native_owned_extent_work` observes five cumulative values under the same
entered original: successful extent allocations, page-rounded allocated bytes,
explicit payload clearing bytes, confirmed extent retirements and retired bytes.
These values do not include the anonymous mapping's initial zero supply, control
writes or nested allocator work. Mapping capacity is not eagerly cleared work.
Retirement does not reset the observations; secure reuse clears its actual
rounded extent again. A failed allocation or unconfirmed retirement adds no
successful work. Overflow makes the observation unavailable and never changes
allocation or cleanup behavior. The observations issue no capacity or ACK and
cannot outlive the actual holding. Its existing final close remains separate.

## Original read/workspace use

The Resource Owner's `borrow_backed_execution_read_use` retains one additional
original `SharedBorrow` of an existing exclusive-write child. It adds no byte
reservation, logical allowance, installation proof or read permission. Only one
such lifetime can be issued for that same child. A pending use blocks parent
delegation settlement before any logical quota or overhead is returned.

Logical stop denies new use while the same physical Owner finishes cleanup.
Only after Root/Reader acknowledgments, last aliases and original context
retirement does `return_backed_execution_read_use_after_owner_ack` return this
additional borrow. It does not settle the parent, close an FD, confirm process
stop or establish a Provider/Store outcome. The original parent cleanup remains
separate. Control/closure/physical overhead still requires real funding and
layout review; this source connection does not adopt a numerical profile.

This generic physical read use is not `FundedReadClaim`, which retains its
existing original-census authentication and restoration contract. A caller
that reads that census must separately retain its authentic original claim.

## Native domain read caller

`prepare_backed_read_context` borrows that original Common read use and stores
it in the existing `NativeBackedExecutionDomain` before physical creation. The
same domain is the partial-failure carrier. Stock builds refuse before this
claim: scoped allocation requires both the exact copied provider and matching
runtime/header flags. No default producer, installed toolchain or runtime
selection is changed here.

`enter_backed_read_context`/`leave_backed_read_context` bracket the whole managed
caller, including UTF-8 input, results and failures. The C-only
`actql_bootstrap_current_read_context` borrows only the same provider's active
TLS context; it is not a wire pointer or a new permission. Filesystem callers
must retain it before their first target allocation/FD and keep their existing
logical closing, current-generation and failure-carrier checks.

`enter_backed_read_cleanup` is only for an existing retained cleanup operation.
It logically stops the Common use without setting physical closing ahead of
Root/Reader acknowledgments. Closing the read context releases its own user
once, waits for active scopes/last aliases, then returns only the extra Common
borrow. A Common-return failure retains the original carrier but does not repeat
an already acknowledged physical retirement. Domain/view/FD/process cleanup and
authority remain separate. Domain close invokes this child-first boundary.

The derived C domain carrier adds context/active/attempt/user/pending-scope
fields, and the Native managed domain adds read-use/attempt/retirement fields.
They need a new actual layout and holding inventory. Existing C9/F4 receipts or
stock layout do not price this new source; normal profile remains `None`.

### Selected bridge conformance

The C-only getter has no arguments and returns an opaque borrowed
`actql_read_context *`, or `NULL` outside the original active scope, on a stock
build or after fork. A filesystem wrapper must reject `NULL` using its existing
typed refusal before allocating/opening, then retain that same context before
its original constructor. The pointer is never a MoonBit/public wire value.
Same-context nested entry is supported; each successful entry needs its original
leave. A getter is not current Account/Source permission or a cleanup ACK.

`fixtures/backed_read_bridge.c` selects four independent C cases: actual managed
Bytes aliases, a retained cleanup user, preparation exhaustion without a fresh
claim, and balanced nested scope/early parent-close rejection. It includes the
matching copied `bootstrap_stub.c` via `BOOTSTRAP_SOURCE`, and includes the copied
provider exactly once via `ACTQL_SCOPED_READ_PROVIDER`. Compile it with the
verified derived header/provider and `ACTQL_SCOPED_READ_ALLOCATOR`, C11/O0,
`-fwrapv -fno-strict-aliasing`, the original allocator selection and selected SDK.
Link only matching derived runtime objects and the pinned original runtime
archives. Stock-header runtime objects or fixture objects containing another
`main` are not interchangeable inputs.

At source `0dc0be38e8b5ac6ce842fa1871b0179d0c67f04e`, `run-yGPPxw` compiled one
fixture, linked once and passed **4/4** under non-Heavy outer60/TERM5 and cumulative
child50/j1. It reused the separately verified five `run-IIAMdL` runtime objects;
these were not rebuilt or relabeled. The original 64-page FD fixture and
16-page payload remain fixture geometry, not a product profile. An extra C user
stands in for a filesystem Owner in the cleanup case; an actual Root/Reader or
positive managed Common-to-C read caller was not executed. The earlier
`run-oYKTjR` fixture compile failure is preserved with zero cases executed.

Workspace evidence is under
`reviews/2026-10-10-python-client/native-backed-read-bridge`: immutable snapshots,
plans, dependency/object/executable digests, complete outputs and release checks.
Native strict/stock13 and source-mutation7 are separate checks. Engine, worker,
installed wheel and public Python E2E remain **0**, with normal profile `None`.
