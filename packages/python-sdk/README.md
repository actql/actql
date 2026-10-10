# ActQL Python Remote Client

This development package connects directly to an existing HTTPS ActQL Host.
It has no embedded Local engine, Node dependency, CLI subprocess, or automatic
submission retry. It is not published to PyPI yet.

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

Closing the Client or reader releases its local connection resources. It never
cancels a Run, proves Host cleanup, or resends an unknown operation. Explicitly
call `run.cancel()` to request cancellation. Keep the original submission and
cancellation references for lookup after response loss. A `not_found` lookup
grants no permission to retry a write.

Use `async with result.rows() as reader` or `with result.rows() as reader` when
streaming, especially when stopping early. Each reader retains one `attempt_id`;
`delivery_attempt()` looks up that attempt without opening another read. A stream
without the protocol's completion marker is incomplete, even after valid rows.
Collection limits fail rather than silently returning a truncated success.

`check(input, kind="text" | "program", scope="template_only" | "bound_input", ...)`
does not execute. Text calls also select `format="sql"` or `"aql-text"`.
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
