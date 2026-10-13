# ActQL Python Local runtime recipe

This package supplies installed component resources for `actql`.
It shares the standard product and SDK release version and pins Wasmtime 38.0.0. Importing either
`actql_sdk` or `actql_local_runtime` does not load Wasmtime or DuckDB. Remote-only
installation keeps its existing dependencies.

This source directory is a recipe, not a shipped runtime. It contains no Wasm
module or native library. A release producer must supply the exact committed
source artifact and its independent build and execution receipts. The existing
Core loader validates ABI70; an older module is not a fallback. Installed
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

The supplied directory contains `artifact.json`, `client_host_wasm.wasm`,
`libduckdb.dylib`, `LICENSE`, `DUCKDB-LICENSE`, `MOONBIT-CORE-LICENSE`, and
`MOONBIT-CORE-NOTICE`. The closed manifest contains these fields:

- `source_sha`: the complete clean recipe/source commit.
- `package_version`: the SDK/runtime release cohort version.
- `platform`: `darwin-arm64`.
- `core_abi`: the existing private Core ABI, currently 70.
- `wasmtime_version`: `38.0.0`.
- `module` and `duckdb`: `{file, bytes, sha256}`, with the fixed filenames above.
- `duckdb_version`: the actual library's `vMAJOR.MINOR.PATCH` string, independently
  checked by the existing library loader when loaded.
- `notices`: exactly the four notice filenames and their SHA-256 hashes.

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
