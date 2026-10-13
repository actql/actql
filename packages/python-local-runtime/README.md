# ActQL Python Local runtime recipe

This package supplies installed component resources for `actql`.
It shares the standard product and SDK release version and pins Wasmtime 38.0.0. Importing either
`actql_sdk` or `actql_local_runtime` does not load Wasmtime or DuckDB. Remote-only
installation keeps its existing dependencies.

This source directory is a recipe, not a shipped runtime. It contains no Wasm
module or native library. A release producer must supply the exact committed
source artifact and its independent build and execution receipts. The existing
Core loader validates ABI73; an older module is not a fallback. Installed
metadata must select standalone DuckDB `v1.4.3`; other library versions cannot
enter this installed profile. The physical loader also checks the actual
library version before use.
Component checksums establish package integrity, not current publication permission,
Run admission, durable ACK, or product acceptance.

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
- `core_abi`: the existing private Core ABI, currently 73.
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

The image compiler, actual installed image execution and capacity supplier
remain unverified until their matching physical acceptance. Native config,
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
or create an Engine. Compilation uses the same selected Engine adapter as the
installed constructor, reuses the existing Core module signature validator,
and serializes without creating a Wasm instance, Store, Run or Submission.
Receipt issuance follows native cleanup and a second original-material fence.
The selected source-original recipe remains unavailable until reviewed; this
script never supplies fixture values or runtime defaults for missing bounds.
Actual `--compile` and wheel generation use the coordinator's finite lane.

Private ABI73 projects a separately declared physical Host baseline into the
same initial Core Root as the existing16MiB VM and12MiB transfer pool. It keeps
that reservation through native Store/Engine destruction; logical pool close
only marks cleanup pending. A zero baseline remains the declared raw diagnostic
subset, never a product profile. The selected physical supplier must fund
bootstrap before VM construction: this later Root projection does not supply
that missing pre-root fact. Product capacity numbers and the selected allocator
original remain unadopted, and ordinary installed construction still refuses
before image capture or native initialization.
