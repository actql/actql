# Native preRoot allocation preparation

This directory is an **uncompiled, unadopted source candidate**, excluded from
the runtime wheel. It changes no installed loader, public API, capacity profile,
fuel, buffer limit, Core ABI or currently selected Wasmtime library. It does not
provide the complete preRoot supplier. Do not enable or build the proposed
Wasmtime patch as an installed runtime recipe yet.

## Actual holding and allocation seam

`owned_capacity.c` proposes one Darwin arm64 anonymous mapping acquired before
image capture. The mapping includes its control records and all child extents;
it never calls malloc or creates another mapping for child allocations. Extents
are page-rounded slices of that original mapping. This is actual owned virtual
memory capacity, not a claim about universal RSS, physical RAM commitment or
immediate garbage collection. The capacity argument remains unadopted.

The private caller must hold a nominal, non-copied native handle. Generation and
recipe bytes are supplied only by the trusted installed configuration. They are
not user claims or authorization evidence. Transfer succeeds once for the same
generation and recipe. Native call scopes reject nested entry from another
lease. Closing waits for scopes to leave and children to retire; a failed
mprotect or munmap retains the same pointer and mapping. Close takes an owning
pointer slot and clears it only after success. Arbitrary stale raw pointers are
not accepted public inputs, and are not made safe by the C interface.

The physical allocator records extents to manage its memory. They do not issue
capacity permissions, Account decisions, Run transitions or cleanup completion
for the common Owners. The original LocalCore remains responsible for native
handle order and Store-last cleanup. Engine wrapper release is not proof that a
Store's Engine clone has been destroyed. The outer lease must remain held until
all native handles and their retained children have actually retired.

## Pinned upstream contact points

`source-inputs.json` binds the reviewed source to Wasmtime 38.0.0, upstream Git
commit `399f857f28ee8845d0cfd4ec71680912b5375831` and the original crate bytes.
`wasmtime-mmap-review.patch` is an exact one-file patch against that crate's Unix
Mmap source. It is a proposed patch surface, not an adopted engine fork.

| Allocation | Existing source path | Candidate physical consumption | Still required |
| --- | --- | --- | --- |
| Pool linear-memory slab | `runtime/vm/instance/allocator/pooling/memory_pool.rs`, `MemoryPool::new` | `Mmap::accessible_reserved` reaches a slice of the original mapping | Same selected Engine entry scope; original guard/layout/current rules |
| Table slab | `runtime/vm/instance/allocator/pooling/table_pool.rs`, `TablePool::new` | Same Mmap slice allocation | Selected target's element size and finite table counts |
| Native code/image copy | `engine.rs`, `Engine::load_code_bytes`; `runtime/vm/mmap_vec.rs` | Same page-rounded original mapping; original code publication/cache coherence retained | Exact source image and native library recipe; image capture below |
| Rust instance metadata and scratch | `pooling.rs`, Vec/Box/Arc and dependency allocations | **Not connected by the Mmap patch** | A real native heap allocation route into the same holding, including alignment, realloc overlap and destruction after call scopes |
| Initial encoded image and ctypes copy | SDK `_local_engine.py`, Wasmtime Python `_module.py` | **Not connected** | Capture into an owned native slice before deserialize, no uncharged `bytes`/`from_buffer_copy` replacement |
| Python, SQLite, dynamic loader and native registrations | Existing bootstrap/Store and runtime dependencies | **Unknown; not zero** | Exact declared allocation/scratch supplier and phase envelope |

The Mmap candidate refuses file mapping and file-backed memory images in its
selected feature path. It does not silently route those to the system allocator.
Memory protection and code cache coherence keep the original Wasmtime methods.
A failed Mmap retirement stays in the native lease for final cleanup retry.
The patch does not intercept Rust heap allocations or prove their absence.

## Required installed connection

The final `InstalledLocalHost.installed` sequence must be:

1. Validate the installed source/cohort, component and engine recipe bindings
   with bounded existing metadata capture. No Engine or encoded image capture.
2. Acquire the actual physical holding from the trusted selected allocator.
   Acquire must fail before Engine/image work if a complete supplier is absent.
3. Capture image and construct native configuration/Engine/Store/module under
   that original lease. Every native operation and callback reentry must use the
   same nominal lease; foreign or missing scope is refusal, never fallback.
4. Transfer once to the existing LocalCore and bind the holding projection to
   its original initial Root. ABI73's resident number is only a projection; it
   neither acquires physical capacity nor funds an earlier allocation.
5. On initialization or cleanup failure, retain the original LocalCore, lease
   and failed handles. After original Store-last native cleanup and pending
   physical extent cleanup succeed, release that same lease exactly once.

The existing Root still decides capacity for Run/task/workspace. A suballocation
of an already held region is not another Root charge; simultaneously held
distinct copies must be represented separately. Phase maxima and resident
projection require a reviewed original, not a number chosen to pass a fixture.

## Build and recipe review before adoption

The pinned source patches, allocator source digest, final C API cdylib crate,
complete Cargo.lock/dependency tree, Rust toolchain, macOS SDK/deployment target,
feature closure and allocator ABI must be fixed before a native build. The
crate archives alone do not supply the full final artifact workspace. No
toolchain version or heap allocation hook is inferred from their names.

The current stock Wasmtime 38 library digest cannot stand for a patched library.
The reviewed image recipe must bind the changed library, allocator ABI/source,
engine configuration, target/CPU, original raw module/source/cohort and new
compiled image. Producer and installed consumer must select exactly that recipe.
Missing/foreign bindings refuse; no stock JIT, old image or repository fallback.
The packaging bridge must include the reviewed native library with its notices
and component digests in the default same-cohort runtime wheel. Users do not
select an allocator or provide paths. No such build or packaging is implemented
or executed by this preparation.

## Required physical counterexamples, not yet executed

- Holding acquisition failure occurs before image capture and Engine creation.
- Wrong recipe/generation and second transfer fail without a replacement lease.
- Pool/table/code and heap/image scratch use addresses in the same holding;
  exhaustion never allocates outside it.
- A foreign callback scope cannot allocate from the original lease.
- Initializer failure retains the same native holding for cleanup retry.
- Live children or active calls prevent final release. A retired child's cleanup
  failure retains its original extent; retry and successful double-close do not
  create or free a second mapping.
- A failed Store close retains the Engine clone and original Root/holding;
  later success releases them once without reopening a Root or cancelling Run.
- Unknown baseline, missing full allocation route or an unadopted profile fail
  before runtime entry. They are not replaced by an unused arena or ABI73.

Patch applicability and source digest checks are preparation evidence only.
Native compilation, physical allocation tests, Engine cleanup, actual 100M fuel,
ordinary wheel installation and public Python Local E2E remain unverified.
