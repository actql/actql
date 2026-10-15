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

The candidate enables SQLite's existing `SQLITE_ENABLE_MEMSYS5` and supplies a
non-null, aligned heap with `SQLITE_CONFIG_HEAP` before private initialization.
`SQLITE_ZERO_MALLOC` remains enabled: an absent heap never selects a system
allocator. The explicit private `heap_bytes` argument selects a partition of the
already backed original Domain; it is not a quota, admission or normal profile.
One original scoped-provider extent is acquired once. No second extent, implicit
growth or fallback satisfies an exhausted engine/adapter request.

The candidate fixture partitions its unchanged 64 host pages into a 32-page heap
and at most 32 pages for the original domain/context, managed controls, paths and
copied result aliases. This is a finite diagnostic partition, not a selected
product profile or a claim that the heap covers VM/FD/WAL/loader resources. No
phase is added to the ceiling. For heap size H and the selected 16-byte minimum
block, pinned MEMSYS5 uses N=floor(H/17) blocks: 16*N bytes of pool and N control
bytes, leaving H-17*N bytes inside the same extent. Buddy power-of-two rounding,
fragmentation and realloc's simultaneous old/new blocks consume that pool;
SQLite memory-status accounting stays enabled. Provider page rounding is applied
to the whole extent once, not to each internal block. Upstream's static allocator
controls remain component data, separately from the funded heap.

Engine scratch, DBs/statements and Native adapter text/diagnostic/result buffers
use this same configured instance. Internal free only makes a block reusable
inside that heap; it does not return the original holding. The API borrow and
SQLite live-memory check fence shutdown. After successful original shutdown,
close requests retirement from the SAME provider and lease and retains the
original heap pointer/context user if physical retirement fails. A retry only
retries that retirement; it does not repeat shutdown, configure or acquire.
Component close neither closes the borrowed context nor returns its backing
loan. Managed result Bytes are separate copies allocated by the original
provider; their own context aliases can outlive the heap and module and still
prevent the original domain's final cleanup ACK. Inherited-process component
calls refuse before entering SQLite or inspecting a buffer.

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
diagnostic and result allocations use the same MEMSYS5 instance after binding;
pre-bind loader text uses the original scoped provider explicitly;
legacy Library allocations keep their original malloc/free paths. There is no
global allocator macro redirect. Managed result Bytes remain original-context
aliases after native buffer/module retirement.

The typed Native `load_current_component_with_custody` entry distinguishes
refusal before any Library acquisition from the original partial Library that
still requires cleanup. Its failure carrier only retries `Library.close_checked`;
it cannot load/configure/adopt another component. Missing original selected scope
refuses before path encoding. Native and unsupported-target APIs do not select a
fallback. The ordinary installed/public factory still does not select this
candidate. A trusted installed
supplier must still verify and retain its owned staged module/source/recipe,
Host/Store/epoch/current and nominal resource use before this physical entry.
Legitimate callers retain every partial Library/Database until checked cleanup
ACK; dropping a failed object/finalization is not an ACK or recovery mechanism.
No default loader or SDK fallback enables this candidate. Root/Reader, managed
Bytes, FD/WAL/loader/control and OS-owned allocations retain their separate
responsibilities and unverified funding; normal profile stays None.

The independent C fixture uses an original 64-host-page provider and prepares thirteen
cases: failed physical heap retirement/retry, null-heap refusal, original heap custody, missing current, one binding, concurrent binding, retained alias/close, resize failure,
exhaustion, initialization exhaustion/partial cleanup, foreign current, fork
refusal and integer boundaries. These establish
only the component memory-method boundary when actually executed. Source-stage
mutation tests establish no Native execution. No Engine/VM/worker/wheel/SELECT1
or whole-process funding follows from either check. The existing 100M fuel,
12MiB/16MiB bounds and normal `None` refusal are unchanged.

The separate `fixtures/library.c` consumes the actual Native adapter and selected
candidate, including explicit adapter buffers and managed aliases. It prepares
nine cases: failed physical retirement/same-Library retry, missing current, buffer alias, partial open, original journal CAS,
foreign current, live-statement close, adapter heap aliases, and lost COMMIT reply/same-key lookup.
The latter uses the existing test-only reply fault and an exec counter; it is
not a real transport failure or durable filesystem/restart acceptance. All
SQLite databases in this fixture are new in-memory databases, never old Runs or
journals. A fixture-only dylib (not a provider or product dependency) holds both the
fault state and the Mach-O interpose. The initial main-executable-only injection
did not affect the provider and is retained as failed diagnostic evidence.
The dylib interpose fails one original provider `mprotect(PROT_NONE)`
for the selected 32-page heap. It checks the real physical-error return, retained
same context/Library and exactly two retirement syscall attempts; no second
shutdown, replacement allocation, module close or success ACK occurs on the
failed attempt. This diagnostic is not a new provider or product fault hook.
Counts become evidence only after the actual bounded execution.

The original one-provider-page-per-allocation Source `462642464a8625a0077fb3e4d6792c185654072f`
passed its component C10 and the first Library C3, then failed real schema
initialization with OOM. Its module, raw failure and subsequent unchanged legacy
callback C26 remain separate evidence. They do not establish this MEMSYS5
candidate's schema/CAS or cleanup behavior. New counts require execution at the
new source and artifact identity.
