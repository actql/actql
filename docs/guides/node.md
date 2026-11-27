# TypeScript and Node

`@actql/node` runs ActQL inside your application: no server, no daemon, the
engine is a library. The same client connects to a remote Host or ActQL Cloud
by changing the connection options. This guide describes day-to-day v0.1
target usage. The shipped declarations describe the current typed API;
sections marked as target-only are not available in the current client.

```sh
npm install @actql/node
```

## A short query

`open()` gives you the shortest path: a local engine with its state in a
directory, and `sql()` / `aql()` for one-off queries.

```ts
import {open} from '@actql/node';

const db = await open({stateDir: '.actql-node'});
try {
  const rows = await db.sql('SELECT @owner AS owner', {owner: 'kim'}, {
    parameterDeclarations: {owner: {type: 'string'}},
  }).all();
  console.log(rows); // [ { owner: 'kim' } ]
} finally {
  await db.close();
}
```

The second argument is always the parameters map. Named parameters need
explicit `parameterDeclarations` in the third argument; values do not infer
their types. This first query is source-free and needs no configured Connector.

`aql()` takes Pipe syntax (`FROM … |> …`); `sql()` takes an ordinary `SELECT`.
Both return a promise of a Result: `all()` reads every row, `rows()` streams
them. The following streaming example requires an already configured
`crm.accounts` source:

```ts
for await (const row of (await db.aql('FROM crm.accounts |> LIMIT 1000')).rows()) {
  console.log(row.id);
}
```

Short queries read; they never write. A Program with an Effect goes through
`startSource` below.

## Connecting

`connect()` is the full client. Locally it is the same engine as `open()`,
with the installation spelled out:

```ts
import {connect} from '@actql/node';

const client = await connect({
  mode: 'local',
  installation: {directory: '.actql-node'},
  profile: 'mock',                 // omit to use the configured connections
});
```

For a remote Host:

```ts
const client = await connect({
  mode: 'remote',
  endpoint: process.env.ACTQL_ENDPOINT,   // configured HTTPS Host URL
  token: process.env.ACTQL_TOKEN,
});
```

`token` can be a string or a function that returns one, so a short-lived
credential can be refreshed. An `actql://` connection string selects a remote
Host as well. Whatever the mode, the rest of the API is the same.

Always await client close, in `finally` or with `await using`. For embedded
Local this closes the owned Host; for a remote client it closes that client's
connection. Closing is not a Run cancellation or Checkpoint approval operation.

An embedded Local client owns its state directory exclusively until its
awaited close completes. Use `.actql-node` separately from a CLI project's
`.actql`; another embedded client or CLI process cannot attach to the running
Host by opening that path. Reopen persisted state only with a compatible
Host implementation and configuration. A remote connection addresses an
already configured Host through its supported transport and authorization;
it does not open a local directory.

## Running a Program

This example assumes `churn-risk.aql` exists and that its required connections
and policy are already configured. It does not install them; use the
source-free query above for a first read without those prerequisites.

```ts
import {readFile} from 'node:fs/promises';

const source = await readFile('churn-risk.aql', 'utf8');
const execution = await client.startSource(source, {
  format: 'aql',
  parameterDeclarations: {owner: {type: 'string'}},
  parameters: {owner: 'kim'},
  stopBefore: 'commit',            // optional: stop before the first write
});
const state = await execution.wait();
console.log(state.status);         // 'succeeded' | 'waiting_checkpoint' | 'failed' | …
```

`startSource` checks the Program and starts a durable Run. `wait()` resolves
at the next **stable state** — waiting for a decision, waiting for
reconciliation, or final — with the Run state: its `status`, its `checkpoint`
while it is waiting, the outcome of each Effect item once they exist, and a
`revision`. If the Run is already stable, `wait()` resolves at once with that
state; `wait({since: state.revision})` waits for the state after it.
`succeeded` means every computation and Effect has an outcome; an
asynchronous Effect may be `accepted` with the external system still
finishing. `execution.ref` is the Run's reference; save it if another process
will need the Run.

Read a named Result after the Run has succeeded:

```ts
const rows = await execution.result('updates').all();
```

`result(name)` reads the Result the Program published with `|> RESULT name`;
a Program that only reads publishes `main`. Reads are bounded: pass
`{maxRows}` or stream with `rows()` for large Results.

### Typed rows

Rows are typed inside ActQL; to carry that into TypeScript, pass a schema that
follows the Standard Schema interface (zod, valibot, ArkType, …) to `all()` or
`rows()`. Each row is validated against it and the result is typed by it:

```ts
import {z} from 'zod';

const Update = z.object({
  id: z.string(),
  risk: z.object({value: z.object({level: z.enum(['low', 'medium', 'high']), reason: z.string()})}),
});
const rows = await execution.result('updates').all(Update);   // Array<z.infer<typeof Update>>
```

A row that does not match fails the read with the schema's issues; nothing is
coerced. The same argument works on `db.sql(…).all(schema)`.

## Checkpoints

When policy defers a write, or you request `stopBefore: 'commit'` in
`startSource()`, `wait()` returns `waiting_checkpoint`. Read the sealed
review before making a decision. This example takes the decision from the
application and uses the configured client's authorized signer.

```ts
import type {Client, Execution} from '@actql/node';

async function reviewEffect(
  client: Client,
  execution: Execution,
  choose: (preview: unknown) => Promise<'defer' | 'approve' | 'reject'>,
) {
  const state = await execution.wait();
  if (state.status !== 'waiting_checkpoint' || !state.checkpoint) return state;
  const checkpointId = state.checkpoint.id;
  const review = await client.reviewCheckpoint(state.checkpoint.checkpoint_cid);
  const preview: unknown = JSON.parse(new TextDecoder().decode(review.bytes));
  const decision = await choose(preview);
  if (decision === 'defer') return state;

  const answer = decision === 'approve'
    ? await client.approve(checkpointId)
    : await client.reject(checkpointId);
  if (answer.results.length !== 1 || answer.results[0].status !== 'committed') {
    throw new Error('The Checkpoint decision was not committed.');
  }
  return execution.wait({since: state.revision});
}
```

Read the review by its Checkpoint CID and send any decision by Checkpoint ID.
Choosing `defer` leaves the original Checkpoint waiting without sending the
Effect. An accepted approval lets that same Run proceed under its sealed
Preview. An accepted rejection cancels the pending Effect. Inspect the Run
state returned by `wait()` for its actual outcome.

The installed Node client accepts decisions through the Checkpoint APIs.
A configured application signer can be passed as `{signer}` to
`approve()` or `reject()`. Use `client.checkpoints()` and
`client.resolveCheckpoints()` to list and resolve Checkpoints across Runs.
See [Effects and approvals](effects-and-approvals.md#approving-and-rejecting)
for the Host policy and signer requirements.

For a review application that delegates delivery to another process,
`signCheckpointAnswer(checkpoint, decision, signer)` signs the exact listed
Checkpoint without sending it to any Host. Read the review before signing.
For an Effect approval pass the original Run's `authorityScopeCid` in the
signer. Retain the original answer and hand it to the authorized
[Remote CLI](../cli.md#share-one-authenticated-remote-host) connected to the
same Host. A local signature alone is not authorization or acceptance.

## Attaching to a Run

A Run outlives the process that started it. From any process, with the same
Store or Host:

```ts
const execution = await client.attach(savedRef);        // execution.ref from earlier
const state = await execution.status();                 // no waiting
```

`status()` returns the current state without waiting; `wait()` follows it.
After a crash, the Run is wherever it was: a waiting Checkpoint is still
waiting, finished work is not repeated, and a write whose outcome was lost is
reported as `needs_reconciliation`:

```ts
if (state.status === 'needs_reconciliation') {
  const after = await execution.reconcile();   // checks with the system; never resends
  console.log(after.status, after.effects);
}
```

`execution.cancel()` asks a Run to stop; the state becomes `cancelled` once
stopping is confirmed.

Starting the same Program with the same `requestId` returns the existing Run
instead of running it again — use it to make a retrying caller safe. The
match is on the whole request: the same Program, parameters, inputs and
authorization scope. The same `requestId` with different content is a
`RequestConflict`, never a silent reuse:

```ts
const execution = await client.startSource(source, {format: 'aql', requestId: 'nightly-2026-10-15'});
```

## Checking without running

`check()` runs the same static validation as `actql check`, with a structured
report of reasons and their locations:

```ts
const outcome = await client.check('SELECT 1 AS n', {
  kind: 'text', format: 'sql', scope: 'template_only',
});
if (outcome.outcome === 'completed' && outcome.report.verdict === 'verified') {
  console.log('Verified');
} else if (outcome.outcome === 'completed') {
  for (const reason of outcome.report.reasons) console.log(reason.code, reason.location);
} else {
  console.log(outcome.outcome);
}
```

`plan()` returns the plan `actql explain` prints, as data.

Reading a file's content, creating one with `SERIALIZE` and collecting a
Result are three different things; [Working with files](../authoring.md#working-with-files)
keeps them apart.

## Errors

Every failure is a `ClientError` with a stable `code`. The ones worth handling:

| Code | When |
| --- | --- |
| `CheckFailed` | The Program is invalid; the report is attached |
| `RequestHeld` | Policy deferred the Run before it started (a pre-Run Checkpoint); resolve it like any other Checkpoint, then `attach` to the Run |
| `RequestConflict` | The `requestId` was used before with a different Program, parameters, inputs or scope |
| `SubmissionUnknown` | The reply to a start was lost. Do not start again with a new request ID; look the request up |
| `ResolutionUnknown` | The reply to an approval was lost; pass the same signed items to `resolveCheckpoints()` without signing again |
| `ClientClosed` | The client was closed |

The rule behind them: a lost reply never means nothing happened. Look the
request or Run up by its identity; never retry a write by resubmitting it.

## Next

- [Quickstart](../getting-started/quickstart.md): the churn-risk Program end
  to end.
- [Local and remote Hosts](hosts.md): connections, credentials and policy.
- [Run lifecycle and recovery](run-lifecycle.md): every state and what to do
  in it.
- [Python](python.md): the same API from Python.

### Bounded text conversion and Unicode normalization

The standard embedded Local runtime includes the bounded text-time policy used by
`TRY_NUMBER(string)`, `ACTQL.NFKC(string)`, and `ACTQL.CASE_FOLD(string)`.
These functions use the portable scalar owner; they do not call a remote
provider, the host's locale routines, or a host Unicode normalizer.

```js
await db.sql("SELECT TRY_NUMBER('12.5') AS amount").all();
// [{amount: 12.5}]
await db.sql("SELECT ACTQL.NFKC('ＡＢＣ') AS text").all();
// [{text: 'ABC'}]
await db.sql("SELECT ACTQL.CASE_FOLD('Straße') AS text").all();
// [{text: 'strasse'}]
```

`TRY_NUMBER` returns `NULL` for invalid numeric text, without trimming or
implicit conversion. It does not catch an error evaluating its argument.
Normalization uses the pinned Unicode 16.0.0 tables: NFKC performs compatibility
normalization; case folding uses full default C/F mappings, not locale-specific
T mappings. Both return NFC.

The installed policy bounds each input at 4,096 Unicode scalars and 16,384 UTF-8
bytes, and each output at 1,048,576 bytes. Existing Run, workspace, live-value and
publication limits still apply. Exceeding a bound fails rather than truncating.
After upgrading the installed runtime, close and reopen the Local Client to use
its current default policy for new submissions. Previously retained Runs keep
their original admitted evidence and identities; reopening does not rewrite
those originals. No state-directory deletion or reinitialization is required.
