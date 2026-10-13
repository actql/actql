# ActQL Python standard product

The standard distribution is `actql`; the lightweight Remote Client is
`actql-sdk`. The standard product depends on the exact same release cohort of
`actql-sdk` and `actql-local-runtime`. Its facade reexports the same Client,
Execution, Result and diagnostic objects. It contains no second engine, Run
owner, scheduler or recovery implementation.

The selected installation forms are:

```sh
uv add actql
```

```python
from actql import Client, AsyncClient
```

For an existing Remote Host without Local components:

```sh
uv add actql-sdk
```

```python
from actql_sdk import Client, AsyncClient
```

The runtime wheel supplies the selected Wasm module, standalone DuckDB and
Wasmtime dependency. Normal users do not build source, run a package recipe,
start another Host, provide a token for Local, or select component paths.
Remote connections continue to use the existing explicit `connect(endpoint,
token)` API.

This candidate is not a completed or published Local release. The public Local
factory, SELECT1 Result/reread, original Run recovery and external installed
consumer remain under acceptance. Metadata, facade import, compiler and private
component checks do not establish that acceptance. The copyable Local execution
example will accompany the verified public factory; no unimplemented API is
advertised here.

The initial runtime recipe selects macOS11 or later on arm64; its platform
wheel has the `py3-none-macosx_11_0_arm64` tag. Python 3.11 is the package minimum;
acceptance identifies the combinations actually tested. Other intended
platforms remain unverified. This source package is a development cohort,
not the existing PyPI name-reservation placeholder and not a publication GO.

Maintainers build all three candidate wheels from the fixed original artifact
with `scripts/build-python-product-wheels.py` using `--artifact-directory ORIGINAL`
and `--destination NEW_COHORT`. The producer retains source, component and wheel
hashes in `cohort.json`, includes only committed SDK/facade source, verifies
runtime bytes after packaging, and performs no execution or publication. A
clean consumer then resolves `actql` from that wheelhouse and separately resolves
`actql-sdk` without the runtime. Those installation/SELECT1/recovery receipts are
required independently of the producer manifest.

For an unpublished fixed candidate, normal dependency resolution uses its complete
wheelhouse, for example `uv pip install --no-index --find-links COHORT/wheels
"actql==COHORT_VERSION"` in a new venv. This does not build source. The fixture
`scripts/fixtures/python-product-installed.py --version COHORT_VERSION --mode
local` requires the actual public Local factory, SELECT1, retained reread and
original Run reattachment; it has no metadata-success fallback. Run `--mode
sdk-only` in a separate SDK-only venv to reject any installed Local distribution.
These fixtures are acceptance commands, not evidence that this candidate has
passed them. Process termination/restart and async coverage remain additional
original completion requirements.
