# ActQL Python Local runtime recipe

This package supplies installed component resources for `actql`.
It shares the standard product and SDK release version and pins Wasmtime 38.0.0. Importing either
`actql_sdk` or `actql_local_runtime` does not load Wasmtime or DuckDB. Remote-only
installation keeps its existing dependencies.

This source directory is a recipe, not a shipped runtime. It contains no Wasm
module or native library. A release producer must supply the exact committed
source artifact and its independent build and execution receipts. The existing
Core loader validates the [generated private ABI](../python-sdk/src/actql_sdk/_local_wasm_abi.py);
an older module is not a fallback. Installed
metadata must select standalone DuckDB `v1.4.3`; other library versions cannot
enter this installed profile. The physical loader also checks the actual
library version before use.
Component checksums establish package integrity, not current publication permission,
Run admission, durable ACK, or product acceptance.

The canonical [Python support matrix](../../docs/reference/status.md#python-backends-and-platforms)
separates ordinary startup, optional owned-Native preparation, supported operations
and candidate-specific evidence. This recipe does not establish those outcomes.

The first physical profile is macOS11 or later on arm64. The wheel uses the
`py3-none-macosx_11_0_arm64` tag; the recipe reads the actual standalone library
architecture and minimum OS before staging. Other intended platforms remain
unverified by this recipe. The universal library's other slice does not add
an advertised Python profile.

## Fixed producer input

The supplied directory contains `artifact.json`, `engine-recipe.json`, `client_host_wasm.cwasm`,
`client_host_wasm.wasm`,
`libduckdb.dylib`, `LICENSE`, `DUCKDB-LICENSE`, `MOONBIT-CORE-LICENSE`, and
`MOONBIT-CORE-NOTICE`. The closed manifest contains these fields:

- `source_sha`: the complete clean recipe/source commit.
- `package_version`: the SDK/runtime release cohort version.
- `platform`: `darwin-arm64`.
- `core_abi`: the same generated private Core ABI required by the SDK loader.
- `wasmtime_version`: `38.0.0`.
- `module` and `duckdb`: `{file, bytes, sha256}`, with the fixed filenames above.
- `duckdb_version`: the actual library's `vMAJOR.MINOR.PATCH` string, independently
  checked by the existing library loader when loaded.
- `notices`: exactly the four notice filenames and their SHA-256 hashes.
- `engine_recipe`: `{file, bytes, sha256}` for `engine-recipe.json`, copied from
  the same clean source's `packages/python-local-runtime/selected-image-recipe.json`.
  That source-original must be explicitly selected before production. No
  production profile is inferred from test scalars or Wasmtime defaults.
- `compiled_image`: the original source/cohort/module/ABI/Wasmtime library,
  platform, exact Engine body and its digest, plus `{file, bytes, sha256}` for
  `client_host_wasm.cwasm`. The inspector requires the selected arm64 ELF object
  architecture as well as the original recipe and component digests.

The fixed cohort builder also places `_local_release_binding.json` in the
lightweight SDK wheel, with the original source, cohort, ABI and artifact
manifest digest. Local resolution checks this before accepting the runtime's
manifest. A same-version changed runtime or missing SDK binding is rejected;
Remote imports and their lightweight dependencies do not load this record.

The closed installed format requires both new fields. An old raw-Wasm-only
artifact is rejected. Raw Wasm remains an original producer input/evidence;
there is no image-to-JIT fallback. Component inspection is not bootstrap
capacity adoption or permission to deserialize native code. The trusted Host
supplier must independently adopt the matching original before VM construction.
The installed constructor is image-only and shares the pinned Engine setting
adapter with the producer recipe. It verifies the selected Wasmtime native
library before import and again before Config/Engine construction, then uses
`Module.deserialize` and the existing strict Core import/export/ABI checks.
There is no raw-module compilation fallback. An unavailable source-original
bootstrap capacity still refuses before image capture or VM creation.

The selected classic-Wasm profile disables GC, components and native async
stacks; their pool counts are explicitly zero because those features are
inactive, not because unknown scratch was measured as zero. The original
16MiB linear-memory limit is also the memory reservation, with no growth
reservation or guard mapping. The Wasmtime38 default 512KiB Wasm stack limit
is recorded explicitly. The 12MiB transfer pool and 100M instruction fuel
remain unchanged. Instance-metadata and table maxima require the separately
reviewed source-original recipe; fixture values are not product defaults.

Image/compiler integrity does not establish installed execution or capacity
adoption. Ordinary platform startup has the limited candidate evidence recorded
in the support matrix; the optional owned-Native preparation supplier remains
incomplete. Each new candidate still requires matching physical acceptance. Native config,
pool, module and Engine cleanup failures retain the original handles through
the existing Core cleanup carrier; they do not cancel or retry a Run.

Do not copy a historical success receipt onto a new module or derive execution
success from this manifest. The final producer and wheel consumer evidence must
identify the actual source, components, build conditions, and tested profile.

## Maintainer preparation

Once the fixed runtime producer is authorized and its original receipts are
retained, stage the package from a clean checkout:

```sh
python scripts/prepare-python-local-runtime.py \
  --artifact-directory FIXED_PRODUCER_DIRECTORY \
  --bindings-source PINNED_WASMTIME_38_SDIST \
  --native-libraries MATCHING_PRIVATE_LIBRARY_DIRECTORY \
  --destination NEW_PACKAGE_STAGE
```

The assembly producer also requires `--image-receipt ORIGINAL_IMAGE_RECEIPT`,
from the same clean source, raw module, selected Wasmtime library and Engine
recipe. Its positive `compiled` fact does not assert Run or product success.
Assembly and staging do not implicitly run the image compiler.

The command only stages and verifies files. It does not compile, load a native
library, execute Wasm, build a wheel, download dependencies, or publish. It
refuses a different source, cohort, component digest, notice, ABI, architecture,
or minimum OS, and refuses unbundled non-system library dependencies.
The maintainer's library directory contains the selected `_libwasmtime.dylib`
and its one `libactql_native_control.dylib` dependency. Their recipe digests,
macOS11 metadata and installed identities must match. The pinned Python sdist
is transformed into the private binding namespace and shipped with the original
Wasmtime notice. The same two input options apply to
`scripts/build-python-product-wheels.py`; users do not supply these paths.
`preparation.json` lists staged file hashes and explicitly keeps
runtime execution and public Local acceptance false.

Wheel generation and a clean external installation require their separately
coordinated validation lane. Normal users will install `actql` and
use the SDK's ordinary Local Client entrance; they will not run this recipe,
provide component paths, build source, start another Host, or supply a token.
The public Local Client and its copyable SELECT1 example are still being
connected and must pass the actual installed-wheel consumer before delivery.

The fixed three-wheel cohort is built by `scripts/build-python-product-wheels.py`
from the same clean source and original artifact directory. Its `cohort.json`
records all three wheel digests and keeps product/recovery acceptance false.
SDK-only installation is `uv add actql-sdk`; it does not select this runtime.

The maintainer-only `scripts/compile-python-local-image.py` prepares the image
receipt consumed by the component assembler. It requires an exact clean
`--source`, original `--core-receipt`, new `--destination`, and explicit
`--verify-only` or `--compile`. Verification does not import the native runtime
or create an Engine. It verifies the original module/source/toolchain/ABI and
selected recipe independently of any installed ordinary Wasmtime package.
Compilation additionally requires `--bindings-source`, `--native-libraries` and
a fresh absolute `--preparation` directory. The same final product staging
routine checks the pinned source/license, target and both selected DLLs and
rechecks the owned copies. It emits the existing private
`actql_local_runtime._wasmtime` namespace without constructing LocalComponents
or claiming an image/physical receipt. This is preparation, not another wheel
or runtime distribution route. The input DLL directory is never loaded.
Only the owned staged provider is acquired; private import occurs inside that
same original holding, and actual Rust/provider linkage is checked before Config.
Foreign/preloaded private namespaces and changed preparation members are refused.
The fresh preparation directory and imported aliases are retained on every
outcome; partial import is sticky Unknown rather than an unload/reimport or
inferred native cleanup. The final image/physical/workspace/Result and normal
wheel/installed gates remain mandatory and strictly stronger.
Compilation uses the same selected Engine adapter as the
installed constructor, reuses the existing Core module signature validator,
and serializes without creating a Wasm instance, Store, Run or Submission.
Receipt issuance follows native cleanup and a second original-material fence.
Compilation also requires the trusted maintainer supplier's already acquired,
unbound holding from the same selected provider. Runtime import, Config, pool,
Engine, module serialization and handle cleanup use that holding's scope.
`_NativeHoldingLease._from_native_provider` moves a trusted supplier's existing
C slot and uses its canonical C symbols, before importing the dependent Rust
DLL. The historical Rust-forwarder and typed child-borrow entrances remain
separate; no symbol fallback or second provider is selected.
Provider correspondence reuses the installed constructor's exact imported
addresses and file checks; it does not manufacture an installed image or Core
identity. A failed or unconfirmed close retains the same handles and holding
in `ImageCompilerCleanupError.cleanup_compilation`, emits no receipt, and does
not repeat an unconfirmed call. Confirmed handle cleanup followed by a known
holding-retirement refusal may retry only that original holding.
The selected source-original recipe remains unavailable until reviewed; this
script never supplies fixture values or runtime defaults for missing bounds.
The standalone CLI's `--compile` uses the existing C provider acquire, not a
declaration as a substitute for backing. It first requires the exact clean Git
original `packages/python-local-runtime/selected-compiler-holding.json`. That
file is currently absent, so compilation still refuses before loading the
provider or importing Wasmtime. There is no CLI capacity default or normal
factory fallback. Its closed fields are `scope: "image_compiler_only"`,
`module_sha256`, `engine_sha256`, `runtime_library_sha256`,
`provider_library_sha256`, `capacity_bytes` and `generation`. Capacity is a
positive signed-64-bit byte count aligned to the actual Host page size;
generation is a positive unsigned-64-bit value. Booleans are not integers.
The selected source's exact raw declaration hash is the C holding recipe,
bound to that source, module, Engine recipe and both libraries. Acquisition
rechecks that exact original, including capacity and generation; a copied
metadata value cannot replace any of those fields before provider loading.

After file-only verification, the maintainer supplier loads that same selected
C provider and physically acquires its extent. A confirmed nonempty out-slot
is moved once through the existing holding Owner initializer, with the object
retained before the move. The actual capacity observation must match before
compiler work. A failed or lost acquire keeps the same provider, out-slot,
original and any partial holding in `CompilerHoldingAcquisitionError`; it does
not reacquire, close an uncertain slot, issue a Core identity or run Config.
Known empty refusal remains distinct from response loss or a nonempty failed
slot. A pre-acquire provider fence failure retains the loaded provider without
claiming an acquire attempt. Existing compiler cleanup custody then owns the
confirmed holding through serialization and confirmed retirement. A second
preflight failure cleans up only that original; an existing unconfirmed
compiler cleanup carrier is propagated without another close.

This is a maintainer-only physical extent. Loading the provider, including its
pinned MoonBit process initializer, belongs to the separate trusted maintainer
control envelope. The extent does not pay for Python, OS loader or unrelated
VM domains, provide product Host/Run funding, or select normal numerical
allowances. Maintainer resource-guard reservations and eventual product
bootstrap funding are separate; neither verify-only nor scalar custody tests
establish their completeness.

Module preparation precedes physical acceptance. The existing component
producer can record `--record-module-original --source SOURCE --compiled-source
BUILD_SOURCE --module MODULE --link-response ACTUAL_RSP --moon-home PINNED_HOME
--destination MODULE_RECEIPT`. Run it after the normal pinned module build and
retain that build's result. Its closed `compile_only_module_inputs` scope binds
the regular module, complete selected source membership, toolchain/installed
marker and executable versions/bytes, generated ABI freshness, actual link
response/output and every original `.core` input. It records correspondence;
it does not reconstruct a compiler read trace or assert physical success.
Input-equivalent reuse retains the actual `compiled_source_sha` separately
from the current selected source. Added or changed selected inputs refuse it.

The image compiler's existing `--core-receipt` accepts that verified compile-only
original or the stronger physical receipt through one shared module verifier.
It still requires the same recipe, runtime/provider libraries and original
holding. Final component assembly only accepts the physical receipt: it must
embed that same module original and successful contract/result/physical/workspace
observations for the exact source/module. A compile-only receipt, renamed scope
or missing physical cases cannot form an artifact. Neither stage changes the
installed image-only loader or supplies a normal numerical capacity profile.

Private ABI73 projects a separately declared physical Host baseline into the
same initial Core Root as the existing16MiB VM and12MiB transfer pool. It keeps
that reservation through native Store/Engine destruction; logical pool close
only marks cleanup pending. A zero baseline remains the declared raw diagnostic
subset, never a product profile. The selected physical supplier must fund
bootstrap before VM construction: this later Root projection does not supply
that missing pre-root fact. Product capacity numbers and the selected allocator
original remain unadopted, and ordinary installed construction still refuses
before image capture or native initialization.

The standard wheel cohort also requires the trusted source original
`packages/python-local-runtime/selected-host-capacity.json`. The original is
currently absent: staging refuses rather than using fixture allowances. Its
closed private fields are `platform`, `backend`, `allocation_domain`,
`engine_recipe_sha256`, `host_capacity_bytes`, `bootstrap_execution_bytes` and
the six existing `LocalCoreResources` fields under `root`. It selects
`darwin-arm64`, `wasmtime-precompiled-pooling` and
`host-owned-reserved-capacity`; the Engine recipe digest must match the same
artifact. These are installed Host restrictions, not a new Wire contract,
allocator implementation, authority or Run admission.

The cohort builder verifies that bounded file against the exact clean Git blob
before creating a stage. It preserves the original bytes in the SDK's generated
`_local_host_capacity.json`, attaches source/version/ABI/module/Engine context,
and binds its digest in `_local_release_binding.json`. Both actual wheel members
are checked after packaging. The argumentless factory selects that original
before image acquisition and projects its lifetime allowance at the first Core
open. The lightweight SDK still has no Wasmtime/runtime default dependency or
native binary. Missing originals, different context or changed bytes are refused;
older SDK bindings without the capacity digest are not silently accepted.

The known44,441,600-byte fresh installation subtotal is only a consistency
floor. It does not supply unknown native/Python/SQLite allowances or prove a
complete Run/read profile. Physical pre-root funding and justification of every
selected numerical allowance remain integrator requirements. Encoding or
decoding the original and a scalar factory test are not installed execution.
The original bootstrap peak and later resident Host baseline belong to distinct
phases. The consistency check requires the selected Root ceiling to cover the
maximum of that bootstrap peak and the known installation overlap plus resident
baseline. It neither sums those phases nor requires temporary image/FFI load
copies to remain in the resident baseline. This comparison still creates no
physical bootstrap reservation and cannot fill an unknown allocator allowance.

Cleanup keeps the original Wasmtime Store until Linker, Module, Engine wrapper
and temporary configuration handles are released. The Store contains its own
Engine clone: releasing the Python Engine handle is not proof that the Engine's
physical allocations have stopped. Final Store cleanup releases that last
instance/Root custody. Failure retains the same Store, Core and pending Root;
retry never reopens Core or repeats release of successful native handles. The
Python handle counterexamples qualify this order only; actual Native/Wasmtime
cleanup and outer bootstrap reservation remain separate physical evidence.

Private ABI74 adds a separate live-child buffer constructor and explicit report
and logical-stop exports. It obtains its bounded Ledger and prepaid VM/Host
tokens only from the fixed installed Host imports. Failed initialization retains
the original frame and blocks scalar-open fallback; logical close never returns
those fixed tokens before parent physical retirement. The diagnostic Python
host supplies typed Unavailable for these imports until its original physical
channel/native issuer is connected. This addition does not adopt a numerical
profile or establish actual VM, wheel, worker or public Local acceptance.
