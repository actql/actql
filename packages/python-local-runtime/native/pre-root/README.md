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

The private physical observation ports report the full original mapped byte
capacity and whether a span lies within one live child extent. Span observation
requires the same current/transferred lease and refuses closing, retired,
foreign and adjacent-but-separate extents. Neither observation identifies a
Guest VM, issues capacity, adopts a profile or proves outside Python/SQLite
funding. A later caller must obtain the actual original VM reservation span
from the same verified native instance before using membership for projection.
Do not subtract a guessed VM span from the mapped total or double-charge a
proved VM suballocation. Child retirement does not shrink the original mapping.

fixtures/span.c prepares21 independent native cases, including retained full
capacity through child retirement/pending close. It is not compiled or executed
by the source checks. No actual native case is inferred from its source count,
Python status doubles, patch applicability or the earlier Wasm artifacts.

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
| Rust instance metadata and scratch | `pooling.rs`, Vec/Box/Arc and dependency allocations | Proposed `owned_heap.rs` in the final C API cdylib; **uncompiled and not adopted** | Exhaustion/fallible boundary, exact complete feature/allocation coverage and phase envelope |
| Initial encoded image and ctypes copy | SDK `_local_engine.py`, Wasmtime Python `_module.py` | Proposed `owned_image.c` captures into the original holding; **uncompiled, SDK call unconnected** | Nominal native pointer borrow into exact C deserializer, original recipe/current fences and lifetime |
| Python, SQLite, dynamic loader and native registrations | Existing bootstrap/Store and runtime dependencies | **Unknown; not zero** | Exact declared allocation/scratch supplier and phase envelope |

The Mmap candidate refuses file mapping and file-backed memory images in its
selected feature path. It does not silently route those to the system allocator.
Memory protection and code cache coherence keep the original Wasmtime methods.
A failed Mmap retirement stays in the native lease for final cleanup retry.
The patch does not intercept Rust heap allocations or prove their absence.

The separate `wasmtime-owned-artifact-review.patch` proposes the actual final
cdylib allocator hook and an explicit non-default feature relay to Wasmtime.
The artifact links the one separately produced Native control/provider dylib;
it never compiles another C holding/TLS copy. The native control component
includes the original image-capture implementation in that same provider. `owned_abi.rs` supplies Rust-exported private
symbols, so the recipe does not assume that symbols from a linked C archive are
automatically exported by a Rust cdylib. `workspace-build-inputs.json` binds seven upstream source inputs, three Rust
source copies and the seven original physical-provider source files separately. This is an additional
source candidate; no final native library has been built or adopted.

The heap candidate places the original lease/extent and layout in an allocation
header inside the same holding. It checks padding, alignment and pointer-size
limits. Realloc allocates the new extent before retiring the old extent, so both
must fit concurrently. Deallocation retains the original lease even outside the
original call scope; it never invokes System or acquires another holding.

**Heap exhaustion is not closed by this preparation.** GlobalAlloc returning
null can reach Rust's infallible allocation error path. That is not a typed
capacity refusal, an Unknown Owner result or proof of cleanup. The original C
API engine constructor also unwraps `Engine::new`. The candidate must not be
adopted until this failure boundary and the finite declared scratch coverage
are closed. Logging an abort as a passed capacity test would be incorrect.

Precompiled loading does not remove all compiler initialization: pinned
`Engine::new` calls `config.build_compiler` when the Cranelift feature is enabled
(the source is in the original pinned crate). That retained domain needs
coverage under the selected recipe. Do not silently disable or substitute the
existing backend to report compiler scratch as zero.

The separate image candidate accepts the original readonly FD lent by the
installed nofollow resolver. It does not open paths, infer a recipe or accept a
user image. Expected bytes, maximum and digest must come from that same trusted
component/recipe, not caller claims. Native pread uses the existing 65536-byte
quantum, preserves FD position and fails on interrupted/failed/truncated reads
without an unbounded retry. It checks regular-file size, EOF, device/inode and
nanosecond mtime/ctime on the same FD and hashes the exact capture. Only final
success seals the original extent readonly. It closes neither FD nor lease.

The output cleanup pointer is published before the next physical operation can
fail. A nonzero status never accepts that pointer as an image. The original
LocalCore must retain and retire it through its same lease. A failed digest
context retirement stays in the native allocator's pending extent records;
no successful image status is returned. The context itself is allocated from
that lease, but the target compiler's stack frame and CommonCrypto's internal
allocation behavior remain unknown. The proposal uses the target SDK's
CommonCrypto API, whose header/library identity and scratch coverage must be
reviewed before native adoption. It adds no custom digest algorithm.

The private SDK now has an installed file-descriptor branch that registers its
original image extent before native capture and its module output slot before
native deserialization. A genuine supplied holding is mandatory on that branch;
the same library receives the original native pointer without a Python whole
image or ctypes image copy. Failed capture/retirement retains the original
extent in the same LocalCore cleanup path. Null module output is not deleted.
This connection has only FD/pointer/status-double evidence, not actual native
capture or an adopted installed supplier. Native code's separate deserialize
copy remains a distinct simultaneous extent.

The original byte-capture diagnostic branch and stock Python Module.deserialize
remain separately qualified. The native descriptor branch never falls back to
either one. Ordinary factory acquisition, before-capture physical funding,
private binding adoption and native generation/recipe transfer remain incomplete.

## Python binding source and one-library requirement

The official Wasmtime Python 38 source artifact is independently pinned to
`75d38a075571756543266df782979fc2204cafd1fb7f3ebbb901e05df916dd34`.
`prepare_binding_source.py` only stages its top-level high-level binding source
and original license for review under `actql_local_runtime._wasmtime`. It
rewrites absolute upstream self-imports into that private namespace, retaining
relative imports and the same binding implementation. It stages no native DLL,
does not import those modules, and changes no installed dependencies or SDK.
The original lazy resolver must verify the adopted same-cohort native component
and full bootstrap supplier before any future private binding import. Namespace
staging does not provide that supplier or adopt the package recipe.

Stock `_ffi.py` loads a DLL relative to its own installed package. Generated
`_bindings.py` then captures 529 DLL functions at import. Setting `ffi.dll` to a
different library afterward does not replace those captured functions and must
not be used to redirect Engine/Store/module cleanup. A handle from the patched
library must never reach a function captured from the stock library.

The original generated bindings require WASI and WAT symbols even when the
selected Guest profile does not invoke those APIs. Their upstream C API modules
are feature-gated. The earlier minimal feature proposal was incompatible with
the whole binding surface and is retained in its original parent history.
The current source proposal preserves the pinned C API artifact's original
default feature list and adds only the owned-capacity feature. It does not
enable logging, infer extra features or handwrite missing symbols. The exact
original feature list and its source digest are in `workspace-build-inputs.json`.
Actual native export/dependency coverage and recipe adoption remain unverified.

Keeping the original compiled C API surface does not change the selected
Engine configuration: parallel compilation, Guest GC, components and native
async remain disabled, with the original pooling limits. Code/dependency and
initializer holdings still need coverage; compiling a feature is not proof that
its baseline costs zero. Compiled availability is not an Account grant or
permission to run WASI, Model or Effect operations. The original Core still
checks the selected Guest import/capability profile.

The original `ci/cbindgen.py` parses the selected C headers using gcc as a C
preprocessor. It must not be run during a compiler exclusion window. If a later
review chooses a smaller surface, that existing generator and the pinned
feature headers must generate it; do not manually trim generated declarations,
ignore AttributeError or fall back to a second library. Before adoption, the
actual final dylib must expose the staged symbol inventory and private allocator
symbols from the same library, with exact source/build/image recipe bindings.

## Required installed connection

The final `InstalledLocalHost.installed` sequence must be:

1. Validate the installed source/cohort, component and engine recipe bindings
   with bounded existing metadata capture. No Engine or encoded image capture.
2. Acquire the actual physical holding from the trusted selected allocator.
   Acquire must fail before Engine/image work if a complete supplier is absent.
3. Capture image and construct native configuration/Engine/Store/module under
   that original lease. Every native operation and callback reentry must use the
   same nominal lease; foreign or missing scope is refusal, never fallback.
   The private Core caller now connects native enter/leave to initialization,
   Core calls and Store cleanup; actual native execution is still unverified.
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

The final artifact `src/lib.rs`, Cargo manifests and original workspace lock
have now been captured from that same upstream commit. Its minimum Rust
version is 1.88.0, which is not a selected build toolchain. No new `cc` dependency or C compilation edge is introduced by the shared-provider
recipe. The retained original Cargo.lock and complete dependency/toolchain
closure still require actual build review; source applicability is not Cargo
resolution or a finished patched artifact. The full workspace dependency source inventory, exact
compiler/SDK, complete native feature closure and numeric profile remain
unadopted. The missing upstream `rust-toolchain.toml` response is retained as
a 404 lookup result, not replaced by an inferred compiler pin.

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

## Original initialized domain borrow

The private physical worker bootstrap may map the original Core-issued writer
window and borrow its already initialized interior allocator. It must first
validate the original child/ticket with the existing backed-delegation
Owner and fund independent process, FD and control overhead. FD, generation,
recipe and payload DATA do not perform that validation or issue a grant.

`borrow_extent_domain` retains the existing relative allocator records and
payload bytes. It creates no mapping, resets no header and reserves no capacity.
A creator-process alias, copied view, untransferred/closing domain, active scope,
foreign layout or second process borrow is refused. The original process PID
is only a physical exclusion check, not durable worker identity or authority.
Parent allocator entry/mutation and domain close are refused while that borrow
is outstanding; they do not take a possibly abandoned child's allocator lock.

`return_extent_domain_borrow` requires the child scopes and original allocations
to retire. Failure retains the same slot and view. Success leaves closing and
one-shot consumption sticky, and releases the physical exclusion only after
unlocking. It does not unmap the child view, close an FD, observe process stop,
settle Common usage or acknowledge a Provider/Store/Run outcome. The original
Owner still requires independently confirmed stop and mapping/FD retirement
before parent settlement. Child death or a lost response retains uncertainty;
this physical slice adds no dead-child recovery or credit reset port.

The sixteen parent/child counterexamples in `fixtures/domain_borrow.c` use a
single 64-page temporary FD and a fork solely as a physical diagnostic launcher.
The child drops its inherited parent mappings, maps only the issued window,
and uses the same provider. This is not the installed worker startup, complete
pre-spawn funding, Wasmtime execution or wheel/product acceptance.

## Child physical borrow record

`owned_domain_borrow` is included once in the same provider. A trusted child
bootstrap supplies zero-initialized, stable, aligned caller-owned control
storage and its independently owned inherited FD, after original Core and
durable launch validation. Fixed material DATA alone is not that validation.
The record retains any partial map and original borrowed domain before a
failure, and refuses copying, reinitialization and cross-process use. It creates
no Ledger, allocator, additional capacity claim or FD.

Close first returns the original domain borrow, then unmaps the same view. A
failed second stage retains the record and skips the completed first stage on
retry. Active scopes may still leave after closing. Successful close does not
close the FD or supply confirmed stop, Common settlement or Run/Store ACK.
The private Python carrier retains its buffer, selected component, descriptor
and partial result; lost returns are sticky Unknown, never an implicit retry.
Its bounded control-copy storage does not adopt ordinary startup funding.

`fixtures/domain_record.c` supplies eight independent syscall-fault/record
cases. Its PID observations are explicit scalar counters; munmap failure is
injected. Different-process validation belongs to the separately qualified
real FD/DLL consumer. Neither fixture is installed worker or VM acceptance.

A child borrow can move once into the existing `_NativeHoldingLease`, preserving
that same record, provider and persistent pointer slot. Native checks the local
one-shot holding transfer against the already transferred parent domain; it
never resets the shared header or reserves another capacity. The moved borrow
cannot independently close or provide another holding. Final close clears its
holding slot only after domain-return and view-unmap succeed. An unmap failure
after domain return retains the original slot and skips that completed stage
on retry. The existing LocalCore cleanup keeps Store last and retries only the
same retained holding after Store success. This connection does not instantiate
Wasmtime, supply a numeric profile or enable ordinary unfunded startup.


## Shared-provider artifact linkage

`owned_build.rs` is a build-time recipe only. For the selected owned-capacity
feature it requires an explicit source-qualified provider directory, rejects a
relative or directive-injected path, missing/empty/symlink provider and foreign
target, and links `libactql_native_control.dylib` with local `@loader_path`
resolution. The ordinary producer must verify the exact provider digest and
source/build-input correspondence before and after Cargo, then package those
same bytes next to the resulting Wasmtime cdylib. This directory is an internal
producer input, never an installed user option or a runtime fallback.

The owned-capacity cdylib uses `@rpath/_libwasmtime.dylib` as its Mach-O
install name, matching the private binding's existing `darwin-aarch64` layout.
The producer must inspect the actual linked identity; a build-directory path
is not a portable installed identity. This does not establish a deployment
target or funding for the provider's independent allocation domains.

The original Native component contains the one C allocator/TLS plus image and
child-record implementation. Rust exports `actql_owned_*` forwarders to that
provider. Dependent-symbol resolution must be independently exercised on the
actual target; source linkage alone does not prove the final Rust artifact.
No actual Rust toolchain, full dependency closure, runtime/profile/image recipe
or public wheel is adopted by this preparation. Unknown domains stay unknown.

`scripts/produce-python-native-provider.py` is a maintainer-only, guarded build
entry for that component. It checks the selected MoonBit installation and exact
clean source, emits the twelve selected packages and regular C link, then builds
the provider and five runtime support sources with an explicit macOS11 target.
It preserves the existing diagnostic omission of the optional debug package
registry, records actual compiler dependencies, and reuses the existing Mach-O
target/dependency inspector. No old runtime support objects are silently reused.
The resulting library has no constructor; building and inspecting it does not
initialize the control component, adopt a numerical profile or fund a VM.
