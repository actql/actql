# Private SQLite source candidate

This is a review candidate, not a selected runtime, installed supplier or normal
profile. It does not change the system SQLite, Python SQLite, Native Library
loader, existing DBs, journal format, CAS, Unknown handling or same-key lookup.

The candidate is upstream SQLite **3.51.0**, pinned by archive SHA256, individual
source/header SHA256 and SHA3-256, and the full upstream source ID in
`source.json`. The official [release page](https://www.sqlite.org/releaselog/3_51_0.html)
publishes the independent `sqlite3.c` SHA3. This is a concrete review input,
not adoption of that version. The selected macOS SDK's Apple SQLite header has
the same version number and a different source ID; they are not interchangeable.
`NOTICE` and the unchanged original source/header notices accompany staging.

`prepare.py --archive <verified-download> --destination <fresh-directory>` stages
only bounded, nofollow, same-FD verified inputs. It verifies the existing
provider source closure without copying another allocator or TLS provider into
the component. It does not download, compile, load, configure or adopt a library.
The archive path is a maintainer recipe input, never public Client configuration.

`component.c` includes that exact amalgamation with all upstream APIs and globals
at internal linkage and hidden visibility. Only the named ActQL wrapper symbols
are exported, including one private in-process API-table borrow. `SQLITE_OMIT_AUTOINIT` requires explicit initialization;
`SQLITE_ZERO_MALLOC` removes a default system allocator fallback;
`SQLITE_OMIT_LOAD_EXTENSION` prevents introducing another extension allocator.
Other upstream defaults, including mutex and memory-status behavior, remain.
No shared SQLite config/shutdown is called.

The wrapper imports the existing scoped physical provider once. It checks actual
loaded symbol origins, requires the original active read context, retains one
original user before configuring memory methods, and permits one initialization
attempt per component lifetime. A nonblocking physical entry fence rejects
competing/reentrant calls, including initialization and close. Busy does not
consume the original buffer or enqueue a retry. A later Host/Run cannot replace
that binding.
The original context physically binds its lease/backing and generation; this
component does not reconstruct those from scalar metadata. The eventual selected
Library caller must separately retain the nominal Host/Store/epoch/current and
trusted installed-source binding before granting access to this private port.
That installed caller and default packaging are **not connected by this unit**.

Engine memory methods and the adapter buffer port share the same allocation
path. Each header and payload consumes an original provider extent. Reallocation
holds both old and new extents simultaneously, preserving the original on
failure. The finite provider's existing rounding/control overhead still counts;
there is no new quota, pooling allocator or larger fixture limit. A free follows
the original allocation provenance, including after the initiating call leaves
or another context is current. It does not route to that other context's heap.
Inherited-process calls refuse before inspecting a header or entering SQLite.

The component close refuses its outstanding API-table borrow or live engine
buffers. Successful private shutdown returns only this component's retained
context user. It neither closes the borrowed context nor returns its backing
loan. Failed physical retirement stays in the original provider's released
extent table for that Owner's existing cleanup.

`api.h` projects the existing adapter's SQLite calls from this same isolated
component. Its checked close uses `sqlite3_close`, which refuses outstanding
statements, rather than acknowledging a deferred `close_v2` zombie. A Library
borrows the table once; the pointer/instance field is physical lifetime metadata,
not serialized identity or Host authorization. The trusted caller holds the
original current scope and serial Library ownership around all table calls.

The private C acquisition in `src/platform_native/sqlite/sqlite_selected_component.inc`
connects the original Native Library/Database structures to that table. It checks
actual component entry/data/function origins and exact source ID; retains its own
original context user before loading; tracks original Database-object custody;
and keeps separate table/engine/module/context cleanup acknowledgements. An
unconfirmed `dlclose` is sticky and never repeated. Busy Database/statement close
keeps the original Library available for same-owner cleanup. Selected text,
diagnostic and result allocations use the original scoped provider explicitly;
legacy Library allocations keep their original malloc/free paths. There is no
global allocator macro redirect. Managed result Bytes remain original-context
aliases after native buffer/module retirement.

This C acquisition has no MoonBit/public factory caller yet. A trusted installed
supplier must still verify and retain its owned staged module/source/recipe,
Host/Store/epoch/current and nominal resource use before this physical entry.
Legitimate callers retain every partial Library/Database until checked cleanup
ACK; dropping a failed object/finalization is not an ACK or recovery mechanism.
No default loader or SDK fallback enables this candidate. Root/Reader, managed
Bytes, FD/WAL/loader/control and OS-owned allocations retain their separate
responsibilities and unverified funding; normal profile stays None.

The independent C fixture uses an original 64-host-page provider and tests ten
cases: missing current, one binding, concurrent binding, retained alias/close, resize failure,
exhaustion, initialization exhaustion/partial cleanup, foreign current, fork
refusal and integer boundaries. These establish
only the component memory-method boundary when actually executed. Source-stage
mutation tests establish no Native execution. No Engine/VM/worker/wheel/SELECT1
or whole-process funding follows from either check. The existing 100M fuel,
12MiB/16MiB bounds and normal `None` refusal are unchanged.

The separate `fixtures/library.c` consumes the actual Native adapter and selected
candidate, including explicit adapter buffers and managed aliases. It prepares
seven cases: missing current, buffer alias, partial open, original journal CAS,
foreign current, live-statement close, and lost COMMIT reply/same-key lookup.
The latter uses the existing test-only reply fault and an exec counter; it is
not a real transport failure or durable filesystem/restart acceptance. All
SQLite databases in this fixture are new in-memory databases, never old Runs or
journals. Counts become evidence only after the actual bounded execution.
