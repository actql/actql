# Python

The `actql` package runs ActQL inside a Python application, with no server to
run, and connects to a remote Host or ActQL Cloud with the same API. It
mirrors the [Node client](node.md) with Python names: `snake_case` methods,
typed dataclasses for states (`dataclasses.asdict()` when you need a dict),
and both synchronous and `async` facades. Use Python 3.11 or later.

## Install a Linux Local candidate

The [Python support matrix](../reference/status.md#python-backends-and-platforms)
lists the Local profiles. The Linux development candidate targets x86-64 with
glibc 2.28 or later and the
[runtime's native dependencies](../../packages/python-local-runtime/README.md).
The normal wheel acceptance ran on Ubuntu 24.04. Local startup refuses Linux
arm64, musl, and other unsupported platforms. Install `actql-sdk` and use its
Remote `Client.connect` where its dependencies are supported.

Use the [Linux wheel archive](https://github.com/actql/actql/actions/runs/44944485617/artifacts/14724082691)
for the verified development candidate. Check the three wheel digests against
`cohort.json`. Set `COHORT` to the absolute path of the extracted `cohort`
directory and `DEPENDENCY_WHEELHOUSE` to an offline wheelhouse with the
third-party dependency wheels for your interpreter and platform. From a fresh
directory, install the product through normal dependency resolution.

```sh
python3 -m venv .venv
.venv/bin/python -m pip --isolated install --no-index --only-binary=:all: \
    --find-links "$COHORT/wheels" --find-links "$DEPENDENCY_WHEELHOUSE" \
    "actql==0.0.1"
```

Run this source-free example with `.venv/bin/python`.

```python
from actql import Client

with Client.open(state_dir="linux-local-store") as client:
    submission = client.new_submission()
    run = client.start_source("SELECT 1 AS n", format="sql", submission_ref=submission)
    assert run.wait()["status"] == "succeeded"
    assert run.result("answer").all(max_rows=1) == [{"n": 1}]
```

The [Linux wheel acceptance](https://github.com/actql/actql/actions/runs/44944485617/job/136969012436)
also exercised typed parameters, active cancellation and cancellation lookup,
first close, and Saved reads from a separate process. The accepted Linux Local
examples in this section use SQL without configured Sources. This wheelhouse
contains an unpublished development cohort.

## Install from a package index

Use the usual dependency commands for packages available from your selected
package index.

```sh
uv add actql
# or
pip install actql
```

## A short query

These Source-backed examples use a configured Remote Host. The Host must
support SQL and AQL against the `crm.accounts` Source, and your account must
have permission to read that Source and its Results.

```python
import os
from actql_sdk import Client

with Client.connect(
    endpoint=os.environ["ACTQL_ENDPOINT"], token=os.environ["ACTQL_TOKEN"]
) as db:
    rows = db.sql(
        "SELECT id, name FROM crm.accounts WHERE owner = @owner",
        {"owner": "kim"},
    ).all()
    print(rows)

    with db.aql("FROM crm.accounts |> LIMIT 1000").rows() as reader:
        for row in reader:
            print(row["id"])
```

`sql()` takes an ordinary `SELECT`; `aql()` takes Pipe syntax. The second
argument is the parameters map. `all()` reads every row; `rows()` streams.
Both run inside the `with` block — the handle is closed when it ends.

Short queries read; a Program with an Effect goes through `start_source`.

## Connecting

The Local connection example requires a configured project and a Local Host
that supplies the selected Mock profile. For the Linux wheelhouse example,
use `Client.open()` with a state directory as shown above.

```python
client = actql.connect(
    mode="local",
    installation=".actql",   # the Store directory
    profile="mock",          # omit to use the configured connections
)
```

For a remote Host:

```python
client = actql.connect(
    mode="remote",
    endpoint=os.environ["ACTQL_ENDPOINT"],   # actql://host.acme.internal
    token=os.environ["ACTQL_TOKEN"],
)
```

`token` may be a string or a callable that returns one, and `endpoint` an
`actql://` connection string or the Host's `https://` URL. Use the client as a
context manager, or call `close()` yourself; closing never cancels a Run.

Inside an event loop use the async facade — the same methods, awaited:

```python
async with await actql.AsyncClient.connect(mode="local", installation=".actql") as client:
    rows = await client.sql("SELECT 1 AS id").all()
```

`client.sql(…)` returns a query handle; awaiting `.all()` (or iterating
`.rows()`) is what runs it, so there is one `await` per read.

## Running a Program

Use a connected Host that supports the Program's AQL, configured Sources and
Effects, with an account authorized for those operations. Use `stop_before`
only when that Host supports Checkpoints.

```python
source = open("churn-risk.aql").read()
execution = client.start_source(
    source,
    format="aql",
    parameters={"owner": "kim"},
    stop_before="commit",        # optional: stop before the first write
)
state = execution.wait()
print(state.status)              # "succeeded", "waiting_checkpoint", "failed", …
```

`start_source` checks the Program and starts a durable Run. `wait()` returns
at the next **stable state** — waiting for a decision, waiting for
reconciliation, or final — as a `RunState` dataclass with `status`,
`checkpoint`, `effects` and `revision`. If the Run is already stable, `wait()`
returns that state at once; `wait(since=state.revision)` waits for the state
after it. `succeeded` means every computation and Effect has an outcome; an
asynchronous Effect may be `accepted` with the external system still
finishing. `execution.ref` is the Run's reference — save it if another process
needs the Run.

Read a named Result after success:

```python
rows = execution.result("updates").all(max_rows=10_000)
```

Reads are bounded; pass `max_rows` or stream with `rows()`. To validate and
type the rows, pass a `schema=`: a pydantic model, or any validator the
Python SDK accepts; a row that does not match raises, nothing is coerced.

## Checkpoints

These examples require a Host with Checkpoint review and resolution enabled
and a signer authorized to resolve the Checkpoint.

When policy defers a write, or you passed `stop_before="commit"`:

```python
state = execution.wait()
if state.status == "waiting_checkpoint":
    ckpt = state.checkpoint
    print(ckpt.id, ckpt.effect.target, len(ckpt.items))
    for change in ckpt.preview.changes:
        print(change.id, change.field, change.before, "→", change.after)
```

Decide from code, or hand it to a person and let this process end — the Run
waits in the Store:

```python
if len(ckpt.items) <= 100:
    client.approve(ckpt.id)
    final = execution.wait(since=state.revision)
else:
    notify_reviewer(run_ref=execution.ref, checkpoint=ckpt.id)
    # Nothing to wait for here. The reviewer approves from the CLI or elsewhere;
    # a later process attaches to execution.ref and reads the outcome.
```

`approve()` and `reject()` sign the decision with the client's configured
signer and bind it to that exact preview. Approving continues the same Run;
rejecting ends it as `cancelled` with nothing sent.

### Deciding from code

The client can also be the decider: `connect()` takes a `decide` function
that the Host calls with the Preview before it stops. It returns `"permit"`,
`"reject"` or `"defer"`; only `"defer"` creates a Checkpoint.

```python
def decide(decision):
    if decision.kind != "effect_set":        # reads, model calls, the Run itself
        return "permit"
    return "permit" if len(decision.preview.items) <= 100 else "defer"

client = actql.connect(mode="local", installation=".actql", decide=decide)
```

`decision.kind` is `"run"`, `"read"`, `"infer"`, `"egress"` or
`"effect_set"`; only an `effect_set` decision carries a `preview`, whose
`items` are the records that would change, `fields` the fields written and
`target` the resource. The function only decides; it cannot change the
Preview, and if it raises, nothing is dispatched.

`client.checkpoints()`,
`client.review_checkpoint(item)` and
`client.resolve_checkpoints(items, signer=...)` expose the same operations with
explicit signing and paging, for review tools.

## Attaching to a Run

```python
execution = client.attach(saved_ref)
state = execution.status()       # current state, no waiting
```

After a restart the Run is where it was. A write whose reply was lost shows
as `needs_reconciliation`:

```python
if state.status == "needs_reconciliation":
    after = execution.reconcile()   # asks the system what happened; never resends
    print(after.status, after.effects)
```

`execution.cancel()` asks the Run to stop. Starting the same Program with the
same `request_id` returns the existing Run instead of running it again — when
the Program, parameters, inputs and authorization scope are the same. The same
`request_id` with different content raises `RequestConflict`:

```python
execution = client.start_source(source, format="aql", request_id="nightly-2026-10-15")
```

## Checking without running

```python
outcome = client.check(source, kind="text", format="aql", scope="template_only")
if outcome.report.verdict != "valid":
    for reason in outcome.report.reasons:
        print(reason.code, reason.location)
```

`client.plan(source, format="aql")` returns what `actql explain` prints, as
data.

Reading a file's content, creating one with `SERIALIZE` and collecting a
Result are three different things; [Working with files](../authoring.md#working-with-files)
keeps them apart.

## Errors

Failures raise `actql.ClientError` subclasses with a stable `code`:

| Exception | When |
| --- | --- |
| `CheckFailed` | The Program is invalid; the report is attached |
| `RequestHeld` | Policy deferred the Run before it started (a pre-Run Checkpoint); resolve it like any other Checkpoint, then `attach` to the Run |
| `RequestConflict` | The `request_id` was used before with a different Program, parameters, inputs or scope |
| `SubmissionUnknown` | The reply to a start was lost. Look the request up; do not start again under a new ID |
| `ResolutionUnknown` | The reply to an approval was lost; resend the same items — the Host recognises the repeat and does not apply it twice |
| `ClientClosed` | The client was closed |

A lost reply never means nothing happened. Look the request or Run up by its
identity; never retry a write by resubmitting it.

## Next

- [Quickstart](../getting-started/quickstart.md): the churn-risk Program end
  to end.
- [Local and remote Hosts](hosts.md): connections, credentials and policy.
- [Run lifecycle and recovery](run-lifecycle.md): every state and what to do
  in it.
