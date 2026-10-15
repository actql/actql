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
are exported. `SQLITE_OMIT_AUTOINIT` requires explicit initialization;
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

The close operation refuses outstanding buffers. Successful private shutdown
returns only this component's retained context user. It neither closes the
borrowed context nor returns its backing loan. Failed physical retirement stays
in the original provider's released extent table for that Owner's existing
cleanup. A DB/statement/callback/VFS API is intentionally not exported in this
memory-method slice; connecting the existing adapter must retain all those
borrowers and partial carriers before adding its operations. Existing adapter
stock text/diagnostic/result malloc paths are therefore **still unconnected**
until that subsequent Library unit uses this port. Managed MoonBit Bytes and
Root/Reader/FD/WAL/loader/control allocations remain separate responsibilities.

The independent C fixture uses an original 64-host-page provider and tests nine
cases: missing current, one binding, concurrent binding, retained alias/close, resize failure,
exhaustion, foreign current, fork refusal and integer boundaries. These establish
only the component memory-method boundary when actually executed. Source-stage
mutation tests establish no Native execution. No Engine/VM/worker/wheel/SELECT1
or whole-process funding follows from either check. The existing 100M fuel,
12MiB/16MiB bounds and normal `None` refusal are unchanged.
