# ActQL Python Remote Client

This development package connects directly to an existing HTTPS ActQL Host.
It does not install a Local runtime, native assets, Node or a CLI subprocess.
It does not retry submissions automatically. This development cohort is not
published to PyPI yet.

The lightweight installation is `uv add actql-sdk`, with `from actql_sdk`
imports. The standard product is `uv add actql`, with `from actql` imports and
the same-cohort Local runtime dependency. The standard facade delegates to this
same SDK; it does not copy its execution or recovery implementation.
The old Local extra is not the current installation entrance.

The standard product's argumentless Local entry is `Client.open()` or
`await AsyncClient.open()`. Calling it explicitly requires the matching Local
runtime and adopted Host capacity originals; it performs no Remote connection
or internal-path fallback. The current capacity supplier is unfinished and
refuses before VM startup. `connect(endpoint, token)` remains the lightweight
Remote entry. Importing this SDK alone does not import Wasmtime or DuckDB.

Python 3.11 or newer is required. Both facades share wire validation, exact
submitted JSON snapshots, operation identities, and bounded Result readers.

```python
from actql_sdk import AsyncClient

async def example(endpoint, token):
    async with await AsyncClient.connect(endpoint, token) as client:
        reference = client.new_submission()
        run = await client.start_source(
            "SELECT 1 AS n", format="sql", submission_ref=reference)
        state = await run.wait()
        if state["status"] == "succeeded":
            return await run.result("answer").all(max_rows=10)
```

```python
from actql_sdk import Client

with Client.connect(endpoint, token) as client:
    reference = client.new_submission()
    run = client.start_source(
        "SELECT 1 AS n", format="sql", submission_ref=reference)
    state = run.wait()
    if state["status"] == "succeeded":
        rows = run.result("answer").all(max_rows=10)
```

Sync calls reject with `SyncClientInRunningEventLoop` before I/O when a caller's
event loop is running. Use the async facade there. The sync facade owns a private,
persistent Runner; it does not stop or nest an application loop.

`run.status()` and `run.wait()` return immutable `RunState` values. To wait
for a later stable observation, pass the original state revision:

```python
previous = run.status()
changed = run.wait(since=previous.revision)
# Async: previous = await run.status(); changed = await run.wait(since=previous.revision)
```

`since` is a nonnegative safe integer. Omission sends JSON null; zero is an
explicit revision. A successful response must be stable and newer than `since`.
The Host may return `WaitTimeout` without changing the Run or
`InvalidWaitRevision` for a future revision. The SDK preserves those errors,
performs no status polling or automatic retry, and does not substitute
`control.revision`. A transport timeout remains an uncertain exchange, not a
Run cancellation or physical-stop acknowledgement. The unfinished Local wait
condition supplier refuses explicit conditions rather than ignoring `since`.

To request the existing Host's stop before the first write, select the closed
literal on the original submission:

```python
run = client.start_source(effect_text, format="sql",
    submission_ref=client.new_submission(), stop_before="commit")
# Async: run = await client.start_source(..., stop_before="commit")
```

The same option is available on `start(program, ...)`. It is a restriction,
not a write grant or a COMMIT acknowledgement; the existing Checkpoint,
Preview and authorization Owners still decide whether execution may continue.
Omit the argument when no requested stop is needed. Explicit `None`, booleans
and other strings are invalid before credentials or transport. The selected
restriction is captured in the same submitted-intent CID. Preserve the original
submission reference after response loss and use lookup; changing the option
does not turn the same original submission into a new authorized operation.

Closing the Client or reader releases its local connection resources. It never
cancels a Run, proves Host cleanup, or resends an unknown operation. Explicitly
call `run.cancel()` to request cancellation. Keep the original submission and
cancellation references for lookup after response loss. A `not_found` lookup
grants no permission to retry a write.

### Configured Checkpoint signer and exact decisions

Configure an application-owned `Signer` on `Client.connect(..., signer=signer)`
or `AsyncClient.connect(..., signer=signer)` (and on the corresponding Local
`open` factory). `Signer.sign` receives the original artifact CID's UTF-8
bytes and returns an Ed25519 signature; async callbacks are supported. The
SDK copies the signer selection, not its private key, and adds no crypto or
Local-engine dependency to the lightweight Remote installation.

```python
from actql_sdk import Client, Signer

signer = Signer("reviewer-key", "reviewer", application_sign,
                authority_scope_cid=trusted_host_authority_scope_cid)
with Client.connect(endpoint, token, signer=signer) as client:
    client.approve(original_checkpoint_id)
    # Or client.reject(original_checkpoint_id).
```

The convenience calls perform one exact pending-ID metadata lookup in the
original Host/Journal and delegate to `resolve_checkpoints`. They do not cache
Checkpoints, search pages, reconstruct a Preview, grant permission or replace
the Host's current Account checks. Effect approval requires the signer's real
authority scope; an ID or signer configuration alone supplies none. The same
configured signer can serve explicit unsigned `resolve_checkpoints` items;
an explicit method signer still overrides it. Already-signed items are not
re-signed.

An absent, fulfilled, cancelled or expired Checkpoint is not a new pending
attempt. Invalid or mismatched lookup responses are refused before signing.
Resolution reply loss remains `ResolutionUnknown` with the original signed
wires retained; there is no automatic retry, new issuance or Effect send.
Client close is not Run cancellation. Failed local cleanup retains the same
signer/transport custody until the original cleanup succeeds.

If connection negotiation fails and physical cleanup also fails, the
`ClientConnectionCleanupFailed` error retains `original_error`, `cleanup_error`,
and `cleanup_client`. Explicitly retry `cleanup_client.aclose()` for async or
`cleanup_client.close()` for sync. This closes the original transport; it does
not reconnect, resubmit, or cancel a Run. A successful retry is idempotent.

Use `async with result.rows() as reader` or `with result.rows() as reader` when
streaming, especially when stopping early. Each reader retains one `attempt_id`;
`delivery_attempt()` looks up that attempt without opening another read. A stream
without the protocol's completion marker is incomplete, even after valid rows.
Collection limits fail rather than silently returning a truncated success.

If cleanup fails, call `aclose()` / `close()` again on the same handle. A failed
connection attempt whose cleanup also fails exposes `error.cleanup_client` for
this purpose. That handle is closed to further requests and can only release
its remaining local resources.

`check(input, kind="text" | "program", scope="template_only" | "bound_input", ...)`
does not execute. Text calls also select `format="sql"` or `"aql"`. The existing `"aql-text"`
spelling selects the same compiler and is preserved in retained requests.
Template calls must omit `parameters` entirely. Changed inputs or bindings require
a new check. `get_check_input()` and the location helpers use only the original
SDK observation; a serialized or copied response has no original-input custody.
UTF-8 spans are interpreted against exact submitted bytes. Editor ranges use
zero-based lines and UTF-16 columns; no exact editor position exists inside CRLF.

The initial implementation is in development. Full Checkpoint and recovery
acceptance and the separate Python Local Wasm probe are not delivery-complete.

For development, install `packages/python-sdk[dev]` in a dedicated venv and run
`ACTQL_PYTHON=/path/to/venv/bin/python node scripts/check-python-client.mjs` from
the repository root. This checks generated contracts, focused boundaries and
typed consumer examples under the repository's bounded runner. It starts no Host
and does not contact a package registry.

### Application row schemas

`result.all(schema=Row)` and `result.rows(schema=Row)` accept a Pydantic v2
model class or a `TypeAdapter`. The SDK invokes `model_validate(row,
strict=True)` or `validate_python(row, strict=True)` and returns that typed
value. Pydantic remains an optional application dependency. A custom schema
may implement the same synchronous `validate_python` method; it must raise
on invalid data and honor `strict=True` without coercion.

```python
from pydantic import BaseModel

class Update(BaseModel):
    id: str
    risk: float

updates = execution.result("updates").all(schema=Update, max_rows=1000)
# Async: updates = await execution.result("updates").all(schema=Update)
```

A mismatch raises `ClientError` with code `ResultSchemaMismatch`, the original
`validation_error`, `attempt_id` and number of valid `rows_yielded`. The SDK
error message does not interpolate private row values. Validation ends that
reader and releases its transport; it does not cancel the Run or retry the
read. Failed cleanup retains the original reader for explicit cleanup retry.

Wire and decoded-row limits apply before application validation. The total
retained-value limit continues to count the original decoded rows even when a
schema returns smaller objects. Objects allocated by application validators
remain application-owned; their size is not a new SDK memory guarantee. A
schema cannot supply a missing protocol completion marker or Host receipt.
