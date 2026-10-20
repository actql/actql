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

The short Local entry is `actql.open(state_dir=".actql")`; it returns the same
context-managed `Client` used by `Client.open()` and `await AsyncClient.open()`.
The Client factories also accept an explicit Store directory. They
accept no endpoint, token, Wasm/library path, resources or allocator options.
Both delegate to the same installed Host and existing Client model. The sync
entry rejects an application event loop before I/O; use the async entry there.

Ordinary Local `open()` selects the packaged platform runtime through the same
factory, using the supported OS/runtime services and the actual Core, Store and
Result resources. It does not require a diagnostic resource supplier. An
independent clean installation of the three normal wheels at source
`7629cfd0edd4d819ecbf387c1b417d7d7e984001` passed public import, fresh
`actql.open(state_dir=...)`, `client.sql("SELECT 1 AS id").all()` returning
`[{"id": 1}]`, and explicit close of that same Client on the selected macOS arm64
platform. That finite execution is separate from factory doubles and compiler
checks; it is not a completed or published Local release.

Fresh-process saved-Run lookup/attach/reread/recovery, Mock, repeated-Host pressure,
other platform combinations and responsiveness remain incomplete or unverified.
The optional owned-Native preparation path retains its separate physical
supplier requirements; its `LocalExecutionFundingUnavailable` refusal does not
describe ordinary platform startup. Private resource fixtures are never a fallback
for either path.

Failed initialization with pending physical cleanup retains
`error.cleanup_client`. Retry `cleanup_client.close()` (sync) or
`await cleanup_client.aclose()` (async) on that exact handle. The cleanup-only
Client performs no profile negotiation, new Host, reconnect, Run cancellation
or unknown write retry. It preserves the same unfinished Core/Host and, for
sync, its original Runner until cleanup succeeds.

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
`scripts/fixtures/python-product-installed.py` requires the actual public Local
factory, SELECT1, retained reread and original Run reattachment; it has no
metadata-success fallback. Copy this exact fixed fixture to the external
consumer. Run each of the following as a separate Python process in the same
installed environment and user account:

```sh
python python-product-installed.py --version COHORT_VERSION --mode local --facade sync --phase initial --receipt sync-original.json
python python-product-installed.py --version COHORT_VERSION --mode local --facade sync --phase resume --receipt sync-original.json
python python-product-installed.py --version COHORT_VERSION --mode local --facade async --phase initial --receipt async-original.json
python python-product-installed.py --version COHORT_VERSION --mode local --facade async --phase resume --receipt async-original.json
```

The private acceptance receipt contains only the original public Submission
and Run references and its producer PID/cohort. It is not an internal Host,
runtime, Store or credential configuration. Initial refuses an existing receipt;
resume requires a different PID and only looks up/attaches the saved references.
It never creates a Submission or resends a Program. Both phases read the exact
expected integer row through the existing bounded `Result.all(max_rows=1)` and
reread the same Named Result, then close through their usual context manager.
A failed or unknown lookup is a refusal of this acceptance scenario, not
permission to submit again. Missing components/capacity or cleanup errors fail
the process rather than producing a success JSON.

Run `--mode sdk-only` in a separate SDK-only venv to reject any installed Local
distribution. These fixtures are acceptance commands, not evidence that this
candidate has passed them. The finite ordinary query/close execution does not
establish the complete sync/async initial/resume scenarios, saved-original
recovery, normal numerical funding or full platform coverage. Those remain
separate product gates; public-call spies and receipt-file tests only prepare
them.
