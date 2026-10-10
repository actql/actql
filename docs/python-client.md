# Python Remote Client

The development `actql-sdk` wheel talks directly to an existing ActQL HTTPS
Host. It contains no Local engine, DuckDB, Node runtime, or CLI subprocess.
Install the reviewed wheel into your application environment; PyPI publication
is a separate release step. Python 3.11 is the declared minimum. Acceptance
records identify the Python/platform combinations actually tested.

## Connection and lifetime

```python
from actql_sdk import AsyncClient

async def execute(endpoint, token):
    async with await AsyncClient.connect(endpoint, token) as client:
        original = client.new_submission()
        run = await client.start_source(
            "SELECT 1 AS n", format="sql", submission_ref=original)
        state = await run.wait()
        if state["status"] == "succeeded":
            return await run.result("answer").all(max_rows=10)
```

The synchronous facade shares the same validation, values, identity, diagnostics,
and reader implementation:

```python
from actql_sdk import Client

with Client.connect(endpoint, token) as client:
    original = client.new_submission()
    run = client.start_source("SELECT 1 AS n", format="sql", submission_ref=original)
    if run.wait()["status"] == "succeeded":
        rows = run.result("answer").all(max_rows=10)
```

Call `start(program, submission_ref=original)` for a structured Program, or
`start_source(text, format="aql-text", submission_ref=original)` for supported
AQL. Submission parameters use the `parameters` argument. Host support and
current authorization determine admission; submitting is not a substitute for
non-executing `check`.

Keep TLS verification enabled. A private Host can use an application-created
`ssl.SSLContext` through `verify`. `token` can be a string or an application
credential callback; it can return an awaitable in either facade. Do not print
credentials, original private inputs, or signing keys to logs.

Sync I/O inside a running event loop raises `SyncClientInRunningEventLoop`
before sending a request. Use the async API there. Sync owns a private persistent
Runner and never stops or nests the application's event loop.

`aclose()`/`close()` releases owned connections/readers, without cancelling a
Run or resending an unknown operation. Explicit cleanup failure retains the same
handle for retry. If `connect` fails and cleanup also fails,
`ClientConnectionCleanupFailed` retains `original_error`, `cleanup_error`, and
`cleanup_client`; retry cleanup on that handle, without reconnecting.

## Original operations and recovery

Create and retain the original SubmissionReference before sending. References
are immutable mappings; for durable application storage, encode only the exact
reference fields and nested epoch, preserving their values. Store them with
access controls. References identify original operations; they do not grant
execution or authorization rights.

A `SubmissionUnknown` error retains `submission_ref` and `attempt_ref`. A
`CancellationUnknown` retains `cancel_ref` and `attempt_ref`. These facts do not
mean that the Host did nothing. Never retry by creating another Submission or
cancel identifier merely because the original reply was lost.

```python
lookup = await client.lookup_submission(original)
if lookup["kind"] == "ready":
    run = await client.attach(lookup["admission"]["ref"])
    state = await run.status()
```

This same lookup/attach works from a new Python process under current
credentials. `not_found`, refusal, conflict, expired epoch, and transport failure
retain their distinct meanings; none implicitly permits resending a write.
Use `run.lookup_cancellation(original_cancel_ref)` for the original cancellation.
`run.reconcile()` connects to the existing Host Owner's reconciliation behavior;
it does not replace that Owner with Python logic.

Cancellation is explicit:

```python
state = await run.status()
answer = await run.cancel(
    cancel_id="application-cancel-id",
    expected_revision=state["control"]["revision"],
    attempt_id="application-attempt-id")
```

Inspect the typed result. Acceptance of the request and a `cancelled` terminal
Run observation are separate facts. A revision conflict must not be converted
to a successful cancellation. Client/reader close is neither fact.

## Bounded Named Results

Choose a published Result by name. `all(max_rows=..., max_retained_value_bytes=...)`
uses the same bounded reader; exceeding a limit raises an error rather than
returning a truncated success. Streaming also supports wire, per-row wire, and
per-row retained-value limits.

```python
async with run.result("answer").rows(max_wire_bytes=65536) as reader:
    async for row in reader:
        consume(row)
```

Use `with ...rows() as reader` and normal iteration for sync. Stopping early
requires explicit close/context exit. The reader retains its original
`attempt_id` and `rows_yielded`. `delivery_attempt()` looks up that original
attempt without opening a replacement reader. A valid row prefix without the
protocol completion marker and completed transport is not a completed read.
Host delivery receipts and what this Python consumer actually received remain
separate facts.

Values preserve raw Unicode, CR/LF/CRLF, NULL, absent keys, and array order.
Numbers use the existing binary64 contract. Non-finite values, negative zero,
surrogates, cycles, custom objects, and integers outside the safe-integer input
range are refused instead of silently rounded. Use explicit finite floats only
when the intended value is exactly representable under that contract.

## Checks and input-bound diagnostics

```python
observation = await client.check(
    "SELECT @x AS n", kind="text", format="sql", scope="template_only",
    parameter_declarations={"x": {"type": "number"}})
```

Every check selects `kind` and `scope`. Template-only requests omit parameters;
a bound-input check supplies the newly captured bindings. Structured Program
checks use `kind="program"` and return JSON pointers, never invented text spans.
Checks, diagnostic lookup, and rechecks do not start a Run or resend a rejected
Submission. Inspect the typed outcome/report rather than inferring success from
HTTP status or prose.

Use `get_check_input(observation, document_id, revision)` and
`resolve_check_location(observation, location)` for the original snapshot.
`resolve_check_text_range` converts exact UTF-8 spans to zero-based line/UTF-16
editor coordinates; a position inside CRLF has no exact editor coordinate.
`explain_check_reason(reason)` returns English catalog text and safe advice.
`get_submission_check(error)` retrieves the original public Check Observation
for a rejected submission when available; use the same location helpers on it.

Copying/serializing an observation preserves public data but does not create
original-input custody. Changed input or a different document revision must not
reuse old locations or fixes. Diagnostic information grants no execution,
re-submission, approval, or Source disclosure permission.

## Explicit Checkpoint decisions

`checkpoints()` lists currently authorized Checkpoints; `review_checkpoint(item)`
fetches and validates the bounded review artifact. Applications inspect the
review and explicitly choose a decision. `Signer` accepts the application's
Ed25519 signing callback and registered key/reviewer identities; the Remote
package does not own or fetch private keys.

```python
from actql_sdk import Signer

signer = Signer(key_id, reviewer_id, sign_ed25519,
                authority_scope_cid=run.ref["authorityScopeCid"])
answer = await client.resolve_checkpoints(
    [{"checkpoint": checkpoint, "decision": "approved"}], signer=signer)
```

The existing Owner verifies authority, exact target/value/version, signatures,
and durable acceptance. Committed approval and completed Effect execution are
separate facts. Reattach the original Run after a Host restart and observe its
state. `ResolutionUnknown` retains the exact signed items; do not manufacture a
new approval or assume the write did not happen. Unknown external outcomes stay
unknown until the existing Host's authorized reconciliation establishes more.

The separate Wasm/DuckDB feasibility experiment is not a Local Client and is
not included in this Remote wheel. Its findings, actual module digest, ownership
limits, and missing portable Client ABI are separate handoff material.
