# Python Local fixed artifact preparation

This is a maintainer recipe for the selected macOS11-or-later arm64 profile,
not public Local Client or wheel acceptance. The standard product is `actql`
with exact `actql-sdk` and `actql-local-runtime` dependencies; the lightweight
SDK does not have a Local extra. Users install a selected exact product version;
they do not build source, supply a Wasm path, or run these producer commands.
The ordinary public Local Client entrance must be completed and independently
accepted from installed wheels before the profile is delivered.

## Original physical inputs

Use one committed clean source SHA for the public SDK, producer, module and
receipts. Select the repository-pinned MoonBit toolchain, an isolated Python
environment with Wasmtime38.0.0, and the standalone DuckDB1.4.3 library.
Do not substitute a Node/Python extension's library or an older module receipt.
The producer imports the existing `LOCAL_CORE_ABI`; it maintains no ABI table.

Under the coordinated Heavy lane, obtain the existing Core physical receipt:

```sh
ACTQL_PYTHON_LOCAL=/absolute/producer-venv/bin/python \
  node scripts/check-python-local-core.mjs --physical-boundary
```

This retains `_build/python-local-core/artifacts/<full-sha>/client_host_wasm.wasm`
and `physical-boundary-receipt.json`, with original source, module SHA256,
pinned compiler and actual buffer/bridge/workspace results. The bridge fixture
uses the existing Core loader, including its ABI check. This is private
physical evidence, not public Local acceptance or a complete ABI campaign.

In that same clean checkout and reserved physical lane, retain the existing
standalone DuckDB fixture's original JSON output:

```sh
/absolute/producer-venv/bin/python scripts/fixtures/python-local-duckdb-physical.py \
  /absolute/standalone/libduckdb.dylib --digest <original-sha256> \
  --version v1.4.3 > /absolute/owned-evidence/duckdb-physical.json
```

The fixture must exit0 and report20 actual standalone cases, matching source,
arm64/macOS, exact library digest and observed version. An interrupted, skipped,
workspace-only or synthetic record is not physical acceptance. Preserve the
command/exit/log and original JSON in the producer's execution evidence.

## Component assembly and wheel staging

With both original physical receipts retained:

```sh
python scripts/produce-python-local-runtime.py \
  --core-receipt /absolute/fixed/physical-boundary-receipt.json \
  --duckdb-receipt /absolute/fixed/duckdb-physical.json \
  --image-receipt /absolute/fixed/compiled-image.json \
  --destination /absolute/new/artifact-directory
python scripts/prepare-python-local-runtime.py \
  --artifact-directory /absolute/new/artifact-directory \
  --destination /absolute/new/runtime-package-stage
```

Assembly uses the existing installed-component, Mach-O target/dependency and
original-notice checks. It hashes and copies the selected unchanged module,
library and four repository notices, then rechecks the copied artifact. It
does not compile, load Wasm/DuckDB, execute a Run, make an ACK, build a wheel,
download or publish. `producer.json` binds artifact/toolchain/receipt digests;
keep its referenced original receipts. Failed output is retained for review,
and an existing destination is never overwritten.

The stage remains source-qualified component material. A release uses the
existing complete product/SDK/runtime wheel builder with a required explicit
SemVer input:

```sh
python scripts/build-python-product-wheels.py \
  --artifact-directory /absolute/fixed/artifact-directory \
  --destination /absolute/new/versioned-cohort \
  --version "$ACTQL_VERSION"
```

Set `ACTQL_VERSION` to the complete owner-selected candidate version. The
shared Node build-time parser supplies the PEP 440 spelling; the installed
Python consumer never requires Node. Native-owned runtime preparation also
needs its original explicit binding/library inputs. Version choice alone
does not select an allocation profile, approve publishing or establish a
working Local installation.

Only the isolated three project manifests, their internal exact dependencies,
and the two package-version fields in staged runtime metadata are projected.
The source artifact stays unchanged. The original component reader admits the
source before projection and reinspects the staged result afterward. Module,
image, native library, engine settings, recipe and source identities must stay
exact. The SDK binding and optional capacity envelope use the resulting fixed
release context. The cohort records both source and projected metadata hashes;
they are provenance DATA, not physical execution or owner approval. A final
version is separately built and accepted; an RC filename cannot be relabelled.

Verify wheel/member digests and install
them into an empty consumer outside the repository. Installation, imports,
public Local execution, Result, recovery and wheel portability remain separate
checks. No physical receipt, synthetic assembly test or header check substitutes
for that installed public consumer campaign.
