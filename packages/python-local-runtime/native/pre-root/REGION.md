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
