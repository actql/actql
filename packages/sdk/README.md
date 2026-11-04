# Lightweight ActQL Client

Install the published Remote-only package with `npm install @actql/sdk`.
It does not include Local execution or DuckDB. Configure an existing authorized
HTTPS Host and a scoped token; this example performs no Runner registration.
For fixed release candidates and publication status, see the
[release guide](https://github.com/actql/actql/tree/main/release).

## Remote quickstart

```js
import {connect} from '@actql/sdk';
const client = await connect({mode: 'remote', endpoint: process.env.ACTQL_ENDPOINT,
  token: process.env.ACTQL_TOKEN});
try {
  console.log(await client.sql('SELECT 1 AS id').all());
} finally {
  await client.close();
}
```

Set both `ACTQL_ENDPOINT` (the existing Host's HTTPS origin, such as
`https://host.example/`) and `ACTQL_TOKEN` (its bearer credential) before running
this Remote example. Neither value is created by installing the SDK. For a
first Local query without a Host or authentication setup, install `@actql/node`
and use its `open()` entry instead.

Configuration failures retain their existing `ClientError.code` and message.
The optional `error.hint` names missing fields and shows a fixed accepted
configuration example, without copying options, connection strings or parser
causes. For example, a Remote connection missing both settings reports
`Missing connection options: endpoint, token.` in its hint. Inspect that hint
instead of logging your connection options or credential.

## Workspace connection strings

An installed Host can expose an explicit service Workspace. Connect with the
application's secret connection string:

```js
import {connect} from '@actql/sdk';
const client = await connect(process.env.ACTQL_URL);
// ACTQL_URL: actql://token:<percent-encoded-bearer>@host/workspace-id
```

Or keep the credential separate:

```js
const client = await connect('actql://host/workspace-id', {
  token: getAccessToken,
});
```

The Workspace must match the credential's authenticated target on every
request. A token getter can refresh a credential for that same target; it
does not acquire renewal permission or switch Workspaces. An embedded DSN
credential and a separate token conflict. Credentials must be percent-encoded
as a component, never by encoding or decoding the entire URL. Do not log the
connection string or commit it to source control.

`actql://localhost:port/workspace-id` connects to an already running HTTPS
Host with normal certificate verification. It does not open a directory or
start a server. Node applications can explicitly select loopback HTTP:

```js
const client = await connect('actql://localhost:8080/workspace-id?transport=http', {
  token: getAccessToken,
});
```

Only the exact `?transport=http` query is accepted. `localhost` is pinned to
`127.0.0.1` without DNS or IPv6 fallback; canonical `127.x.x.x` literals and
IPv6 `::1` literals also work. Remote hosts, port zero and alternate query
forms are refused before a token callback or network request. HTTP uses a
private direct Node connection, not global Fetch/proxy configuration. Browser
builds contain only an unavailable stub and reject this mode before fetching
a credential. HTTPS behavior and certificate checks are unchanged.

This plaintext mode trusts the local OS/process boundary; it provides no TLS
server authentication. Configure the Host's `loopbackHttp: true` ingress and
explicitly bind its caller-owned HTTP server to a numeric loopback address.
Bearer authentication and Workspace checks remain required on every request.
There is no automatic downgrade, redirect, daemon, alternate port or directory.
Existing
`connect({mode: 'remote', endpoint, token})` remains available. This is a
Client library, not a deployed Cloud endpoint.
See [the connection contract](https://github.com/actql/actql/blob/main/docs/design/client-workspace-connections.md).

This lightweight package implements the public Client, Execution and Result
transport API for an already installed Client Host. It contains no Local
kernel, native binding, DuckDB adapter or Cloud policy. The installed Node Host supports Program submission within its
installed profile, durable request lookup and deduplication, active and terminal
Run observations, and published Result reads. Supported Program shapes and
connectors depend on the installation; this is not a claim that every Host
supports every Program. See the [current implementation status](https://github.com/actql/actql/blob/main/docs/reviews/current-product-status.md).

## Read-only Plan and original Run views

On a supporting installed Node Host, `client.plan(program)` reads a checked
compiler-issued static Plan and immutable logical ports without creating a Run
or acquiring Source data. AQL text uses `client.plan(text, {format: 'aql'})`;
SQL uses `{format: 'sql'}`. The map describes original checked operations, not
physical task numbers. An input-only Stage remains an input/output occurrence.

A Host with the original Effect preparation/compiler installed may return the
separate `actql-effectful-static-plan-view/0.1` alternative. Its
`computation.plan_view` is the unchanged computation component, not a full
physical Effect DAG. `effect_set` contains checked declared Mapping targets,
Command Resource kinds and inputs. Current permission/gate/approval and actual
target/value observations remain unknown; sealed Preview is unavailable. A
contract minimum is not permission. This read neither installs an Effect
executor nor enables Effect `run.plan()` recovery on an unsupported Host.

`await run.inspect()` reads the currently authorized original Run. It does not
recompile or execute the Program, acquire inputs, dispatch a Model or Effect,
or change the Run's control revision. Views declare non-atomic, Owner-local
observations; they are not a globally synchronized snapshot or control grant.
Unobserved pending flags are omitted, not `false`.

Both reads accept finite `maxWireBytes`, `maxNodes` and `maxDepth` options.
Run Inspect in this initial slice supports source-free Values
Runs with retained original policy evidence. Records without that evidence and
resuming states without the required original continuation/fence observation
refuse Inspect; ordinary legacy status reads remain available. Durable pause,
step, resume, Sample collection, intermediate retention and cost Guards are not
installed by these read methods. Do not infer their support from schema types.

```js
const plan = await client.plan('SELECT 1 AS n', {format: 'sql'});
const run = await client.startSource('SELECT 1 AS n', {format: 'sql',
  submissionRef: client.newSubmission({nonce: 'original-read-example'})});
await run.wait();
const view = await run.inspect();
console.log(plan.compiled_plan_cid, view.run_ref, view.run_state.status);
```

## Client lifetime

Always `await client.close()` in a `finally` block. Close seals new Client
operations immediately, stops its active row and batch readers, and waits for
their cleanup. `await using client = await connect(options)` uses the same
asynchronous disposal where the language supports it. Returned rows and batches
remain the application's values.

A short `sql`/`aql` call after close rejects with `SubmissionNotSent` and an
underlying `ClientClosed` cause; it does not reach the Host. Other direct Client
operations can reject with `ClientClosed` itself. In a `ClientError` catch,
inspect `error.code` first and, for this locally unsent case, inspect
`error.cause` for the underlying Client error. `SubmissionNotSent` describes
this dispatch attempt, not the durable outcome of a previously used submission
identity; it is not permission to replay that identity.

Embedded Local connections share one compatible Host installation per directory.
Closing one Client does not close its siblings. The last Client waits for the
existing Host's graceful shutdown, including already accepted computation and
physical cleanup. A successful close permits a fresh connection to that directory;
durable request and Result retention still follows the Host's retained policies.
Close does not cancel Runs, answer Checkpoints, reconcile Effects or delete
saved Results. Remote close waits for disposal of this Client's local response
readers; it sends no Host shutdown operation and confirms no remote Delivery
settlement or receipt. Observed cancellation uncertainty stays on the original
read's error and attempt.

When close itself finishes a reader whose iterator disposal or remote stream
cancellation fails, close reports that original read failure after releasing
the Client's confirmed local duties. Multiple such failures are retained in
`cleanupError.errors`. This does not create a retry handle for a finished
iterator or confirm remote cleanup.

`ClientCleanupPending` with `cleanupPending: true` means release was not
confirmed. Keep this Client and retry `await client.close()`; new use stays
sealed. Private provider errors and cleanup handles are not exposed. Do not
replace a retained Local cleanup owner by
opening another Host. The awaited cleanup API changes `close(): void` to
`close(): Promise<void>`; update typed implementations and await cleanup rather
than ignoring a possible rejection.

## Connections

## Short source queries

`sql(text, parameters?, options?)` and `aql(text, parameters?, options?)`
start exactly one source admission immediately. SQL selects `sql`; AQL selects
`aql-text`. Their native `ResultPromise` resolves one selected, available Result
after the existing Run wait. They do not read rows until explicitly requested.

```js
const submissionRef = client.newSubmission({nonce: 'example-1'});
const query = client.sql('SELECT 1 AS id', undefined, {submissionRef});
const requestId = query.requestId; // available before credentials or transport
const result = await query;
const rows = await query.all();
for await (const row of result.rows()) console.log(row);
```

Source, parameter declarations, parameters and query options are captured at
invocation. Collection shortcuts capture read options when called, preserving
the live AbortSignal. Re-awaiting, `Promise.resolve`, and `Promise.all` with the
same query share the same Result. A collection shortcut always observes that
query, even if argument capture failed: the original query rejection takes
precedence; after query success it rejects the captured argument error without
reading. Repeated `all()` calls open independent reads
of that Result, with independent attempt IDs; they never repeat Compute.
The resolved Result is not thenable. An ignored query does not cancel accepted
work, and an ignored rejection follows ordinary native Promise behavior.

The second argument is always the named parameters map. Parameter names such as
`format`, `result` or `requestId` are not interpreted as options. The third
argument accepts `parameterDeclarations`, `requestId`, `signal` and `result`.
There is no parameter interpolation or automatic declaration inference. Raw rows
have `DynamicRow` type; `sql<MyRow>()` and assertion-only `all<MyRow>()` are not
supported. Pass a Standard Schema V1 schema to validate and infer a Result view.

### Validated Result views

`result.all(schema, options?)`, `result.rows(schema, options?)` and
`query.all(schema, options?)` accept a
[Standard Schema V1](https://standardschema.dev/) schema. Types are inferred from
its Output, including transformations. No schema library is installed by the
SDK. Compatible `StandardSchemaV1` declarations are bundled and exported for
custom adapters; schemas from supporting libraries work structurally.

```ts
import type {StandardSchemaV1} from '@actql/sdk';
const ids: StandardSchemaV1<unknown, number> = {
  '~standard': {version: 1, vendor: 'example', validate(row) {
    if (row === null || typeof row !== 'object' || !('id' in row) ||
        typeof row.id !== 'number') {
      return {issues: [{message: 'Expected a numeric id', path: ['id']}]};
    }
    return {value: row.id};
  }},
};
const numbers = await client.sql('SELECT 1 AS id').all(ids); // number[]
const result = await client.sql('SELECT 2 AS id');
for await (const id of result.rows(ids)) console.log(id); // number
```

Validation is client-side, serial and backpressured. Sync and async validators
are supported; empty Results need no validator call. Each view uses the original
Run/Result and one ordinary read attempt. It does not change Host schemas,
serialization, publication, receipts or Compute. It never rereads or reruns on
validation failure. `one()`, `scalar()` and `batches()` remain raw views.

The selected `~standard` receiver, validation method and all supported read
options are captured when the view/shortcut is called, before waiting for a
query. Inherited and non-enumerable options are preserved. The AbortSignal stays
live. Capturing a function does not freeze its closure or library internals.

Within a read, the SDK does not retry a row's Standard Schema validation.
A schema library can perform additional work inside that call, including
invoking an application transform more than once. Prefer validators and
transforms without side effects; do not use callback invocation counts to
trigger external writes or other business actions. Such library behavior does
not represent another SDK read, submission or Compute.

All wire, raw-row and collection ceilings still apply. Raw decoded-value bytes
and collected-row count are charged before application validation, so mutation
or shrinking transforms cannot evade them. Output is not JSON-accounted:
transforms may return Date, Map, bigint, cycles, functions, `undefined`, or even
Promise/thenable values. The SDK preserves those values without awaiting their
contents. Application code that explicitly awaits an output may assimilate it.
Arbitrary callback time, allocation and transformed-output size are outside
raw accounting; `maxRows` still bounds the number collected by `all()`.
`rows()` retains its streaming limits rather than a total collected-row limit.

Schema issues (including an empty issues array), callback exceptions/rejections,
and malformed validation results reject with `ResultValidationFailed` and
`validationKind: 'issues' | 'exception' | 'invalid_result'`. Errors preserve the
original `resultRef`, `attemptId`, zero-based `rowIndex`, and `rowsYielded`.
`issues` retains schema paths for explicit inspection; exceptions remain in the
cause chain. Issues and original callback exceptions are omitted from default
JSON serialization. An invalid schema is `InvalidResultSchema` before reading.
Typed `rows()` counts only validated outputs actually yielded. Failed `all()`
returns none and reports zero, even when earlier rows validated successfully.

Validation failures use the existing reader cleanup owner. A cleanup failure
keeps the primary error plus `cleanupError` and `explainReadFailure(error)`'s
cleanup uncertainty. Multiple cleanup failures are retained as an AggregateError. Aborting a pending validation, or `await client.close()`,
stops the SDK's wait and releases that read through the same cleanup path,
even if the callback's Promise never settles. It does not stop arbitrary
JavaScript, reverse its effects or free allocations still owned by the callback.

Omit `result` only for a Run with exactly one declared Result. Multiple or no
Results yield `ResultSelectionRequired`; an absent selected name yields
`UnknownResultName`. Selection never removes another Result, stage or Effect.
A succeeded Run whose selected storage is unavailable or unknown yields
`ResultUnavailable`, not a new execution.

An Effect-only Program can declare `results: {}` when its Effects pass the
common input, Mapping and Capability checks. Use `client.start(program)` or
`client.startSource(text, {format: 'sql'})` to obtain its Execution; the
`sql()`/`aql()` Result shortcuts do not invent a public Result for a write.
Inspect its status and resolve its ordinary approval Checkpoint. Empty Result
availability does not mean success: unapproved or unresolved Effects remain
blocked, and an unknown commit is reconciled without automatic resend.
Releasing the origin Run does not delete a committed persistent Table.

`result.execution` is the original low-level Execution, and `result.ref` is the
frozen recovery locator `{run, resultName}` using the existing Run reference and
authored Result name. Explicit recovery can `attach(result.ref.run)` and select
`result.ref.resultName` under current authorization. The locator introduces no
new wire identity and grants no read or replay permission.

A returned nonterminal wait is honest: `ExecutionPending` retains preparing,
running or resuming; `ExecutionBlocked` retains a Checkpoint or reconciliation
stop. `ExecutionUnsuccessful` retains failed/cancelled, and
`QueryObservationUnknown` retains an unconfirmed observation. These errors
provide `executionRef` and a non-enumerable live `execution`; an available exact
`observation` and the underlying cause are also non-enumerable. They never change
Run state or automatically poll, submit, reconcile, approve or cancel. A failed
query stays rejected after later approval; follow its original Execution instead.

Before a Run exists, the original `RequestHeld` or `SubmissionUnknown` is
propagated unchanged, retaining its request ID, input and lookup context.
There is no fabricated Execution for a held preparation. Use explicit
`lookupRequest` and attach only after the existing owner returns `found`.

### Development API migration

The former `aql(text, {format, parameters, requestId, signal})` submission method
is now `startSource` with the same arguments and `Promise<Execution>` result.
It supports the existing JSON/YAML/text formats and does not start a wait or
read. Existing Program `start(program, options)` is unchanged. Migrate old calls
explicitly; the new AQL method never guesses whether parameters are old options.
No admission, identity, transport, schema or Host execution path is replaced.

`connect(options)` authenticates with the selected Host and returns its
confirmed owner, durability and capability snapshot. The SDK captures the
profile's scope, limits and capabilities once, validates their unchanged
observation, and retains detached immutable data. Capture or verification
failure rejects the connection with `InvalidHostProfile`; it establishes no
check verdict. The negotiated `scopeRef` identifies connection scope, separately
from a check report's `context_ref` and input revisions. `startSource(text,
{format: "json" | "yaml"})` and `start(program)` send one immutable submission
intent. The Host supplies an authenticated epoch in its negotiated profile.
`client.newSubmission({nonce})` captures that epoch and a caller nonce before
send; omitting `submissionRef` creates a new reference for that call. A bare
historical `requestId` does not create work under a newly negotiated epoch.

Retain the full original reference across reconnects and process restart.
`lookupSubmission(submissionRef)` observes that original submission under
current authorization without starting Compute. A new connection's epoch
cannot replace the saved one. An unknown response or an `unresolvable` lookup
does not prove nonacceptance, and the SDK does not retry automatically.
Profile, submission and lookup replies use the public `@actql/client-wire`
validators, including exact connection, durability, epoch/nonce and intent
bindings. A malformed or foreign acceptance does not become a known Run.

The Client serializes the submitted Program and parameters before awaiting an
asynchronous credential callback, so later mutation of caller objects cannot
change that transmission. `getSubmissionInput(result)` retrieves this call's
detached, deeply frozen JSON request input from its returned Promise, Execution
or original submission error. It includes the full submission reference, nonce,
submission kind, Program or text with declarations, supplied parameters,
connection selection and lookup context. Local and HTTPS use the same JSON-value
snapshot. Text is not normalized or converted to different newlines. Credentials
and signing keys are not added to this snapshot. The accessor does not persist
anything; applications must arrange their own durable input custody.

`getSubmissionOutcome(result)` returns only the validated Owner-issued outcome
received by that original call. `not_accepted` is a durable rejection that
consumes the identity; `preparation_failed` is failure after acceptance. Neither
is inferred from an HTTP error, message or missing record. `preparing` is not a
Run admission. `SubmissionNotSent` reports a local failure before dispatch and
has no Owner outcome; a lost response is `SubmissionUnknown`.

`getSubmissionAttempt(result)` is a separate invocation-bound fact. It returns
`recorded`, `already_satisfied`, `refused`, or `conflict` only after the reply
matches that call's `attemptRef`. Pass `attemptId` in submission options to retain
application correlation; otherwise the SDK creates one before dispatch. This
attempt ID is neither submission custody nor part of the original intent CID.
The original SDK input snapshot retains it, including on unknown responses.

`SubmissionRefused` carries an Owner-issued `attempt_uncommitted_unconsumed`
guarantee for this invocation only. `SubmissionConflict` identifies an
incompatible original intent or restart decision. Neither negates a different
invocation's acceptance. Initial authorization refusal does
not disclose protected original submission fields. These failures have no
`getSubmissionOutcome`: durable `not_accepted` and `preparation_failed` remain
separate original outcomes. HTTP failures, coded exceptions, uncertain COMMIT,
and lost replies cannot manufacture this guarantee. `already_satisfied` returns
the original durable outcome and does not certify execution, physical stop, or
resource release. Lookup remains read-only and returns the original outcome,
without creating another invocation or sending work again.

`explainSubmission` and `formatSubmission` use those admitted branches for
both submission results and `lookupSubmission` results. They distinguish
durable `not_accepted`, accepted `preparation_failed`, accepted `preparing`,
and a validated Run reference. Only the two terminal preparation branches
include their disclosed typed problem. An `unresolvable` lookup establishes
neither nonacceptance nor permission to submit again. A failed exchange or
uninterpretable lookup retains the exact original epoch/nonce and a passive
lookup candidate without acquiring rejected response fields or borrowed causes.
Known unsent attempts describe dispatch only, not the identity's Owner outcome.
These immutable weak associations exist only on the original SDK result or
error; copying or parsing it does not acquire explanatory custody. Formatting
and localization perform no I/O and cannot change the acceptance phase.

`check`, `start` and `startSource` share numeric-preserving JSON request serialization.
NaN, infinities and negative zero are refused, including nested parameters,
Program values, declaration defaults, boxed Numbers and `toJSON` results.
The snapshot is made once before credentials or transport. A submit refusal
uses `InvalidClientPayload`; check retains `InvalidCheckRequest`. Neither is
`SubmissionUnknown`, and neither can reach Host preparation or Run acceptance.

```js
import {getSubmissionInput} from '@actql/sdk';

try {
  const submissionRef = client.newSubmission({nonce: 'original-operation'});
  // Retain this reference with the original application input for restart.
  const execution = await client.start(program, {submissionRef, parameters});
  const submitted = getSubmissionInput(execution);
  // Compare the accepted handle with this call's original input.
} catch (error) {
  if (error.code !== 'SubmissionUnknown') throw error;
  const submitted = getSubmissionInput(error);
  // Inspect the original request; do not submit the edited Program again.
  const lookup = await client.lookupSubmission(submitted.submissionRef);
}
```

`explainSubmission(result)` returns a deeply frozen explanation for that exact
SDK result. The validated submit branch fixes its observation independently of
error `code`, message, severity or HTTP status: `acceptance_unknown` for a lost,
malformed or foreign reply; `run_reference_received` for a validated Run
reference; and `request_held` for a validated held response. The first says that
work may already have started and names the original `lookupSubmission` target and
connection scope. A returned Run reference instead names its read-only `status`
inspection. A held response names request lookup and does not promise a current
preparation or execution state. These are presentation facts from this call,
not a new server acceptance contract or an execution/publication/release proof.

For admitted `not_accepted` or `preparation_failed` outcomes with
`ClientProgramAnalysisLimit` and the `implementation_limit` classification,
`preparationIssue` explains the existing checker analysis-budget fact.
`ClientProgramImplementationLimit` with the same classification instead explains
an unresolved implementation path reported by checking. Both facts are separate
from the Host's independent `ClientProgramUnsupported` feature refusal. This
fact does not establish invalid input, successful checking or execution.
Inspect a check report for outstanding obligations and keep the original
submission reference. A changed input requires a distinct submission identity;
the explanation never retries. Source-dependent budget facts are projected
from the existing audience-filtered public check and rechecked against the
retained original intent during authorized lookup. Raw private Source limits
remain generic when no public budget fact can be admitted.

```js
import {explainSubmission} from '@actql/sdk';

const explanation = explainSubmission(result);
if (explanation?.next.operation === 'lookupSubmission') {
  // Use the original Client and its current authorization for this lookup.
  const observation = await client.lookupSubmission(explanation.next.submissionRef);
  // A missing record does not prove nonacceptance or permit resubmission.
}
```

The helper performs no transport, retry, submit or Compute action. Suggestions
require current authorization when explicitly used. It omits original Program,
text, parameters, credentials and transport causes. Changing a returned error's
fields or observing a later lookup does not rewrite the original explanation.
Copied/deserialized results, attach handles, local payload/credential failures
and user-created errors return `undefined`; this means no bound explanation is
available, not success or nonacceptance. The extra presentation association is
weak and has the same original-result lifetime as input custody. It adds no
Host input storage, public input hash or promised retention period.

The snapshot is local input custody, not evidence that sending, acceptance,
preparation, execution or release succeeded. It grants no lookup, replay or
effect authority. A copied or deserialized handle/error, an attach result or
an error supplied by a credential callback has no association and returns
`undefined`. Reusing another call's error cannot rebind its input.
The SDK retains an association weakly while its original handle/error is
reachable; an application that keeps that result or the retrieved snapshot
keeps its input. It does not impose a fixed retention period or persist the
input. Retaining multiple results can retain multiple inputs; this accessor
adds no aggregate SDK retention limit. Input size continues to be governed by the installed Host's existing
submission limits; this accessor adds no new Host storage or re-fetch API.
The input may contain application secrets, so applications must select what
they display or persist rather than log it wholesale. It is not an
authorization-bound `context_ref` or a new public input hash.

After an unknown response, retain the original connection selection as well:
`lookupContext` identifies
the endpoint and Host-reported scope for investigation, but does not grant
access or authorize looking up the request through a different Workspace or
embedded Host root. Reconnect never submits automatically.

`explainEffectUncertainty(state)` explains an exact validated `Execution.status`,
`wait` or `reconcile` response whose Owner reports `needs_reconciliation` with
`next_action.kind === 'reconcile'`. It retains the Owner-issued Effect names
together with the original Run reference, so a name is never an unscoped write
identity. `physicalStop` is confirmed only by that response's control observation;
missing control or an unknown stop remains unknown. `controlRevision`, when
present, belongs to the Run-control observation. It does not certify an atomic
snapshot across Effect, publication, cancellation or resource owners.

Each attached Execution retains one private Run-control observation. A later
`status`, `wait` or `reconcile` reply with an older control revision, or changed
control facts under the same revision, rejects with `InvalidHostRunState` and
the safe explanation problem `stale_observation`. This includes concurrent
replies that arrive out of order. Duplicate unchanged control facts are allowed;
independent Effect or publication progress and observation timestamps are not
ordered by the control revision. An absent control component supplies no such
ordering evidence and does not reset the retained control revision.

This guard changes no Host state and performs no retry. It retains no history
or new ledger, and it cannot establish a composite snapshot's consistency or
recover missing event history. Keep the original Run reference and explicitly
refresh under current authorization; a rejected reconcile reply does not prove
that the requested reconciliation failed or grant permission to repeat it.

```js
import {explainEffectUncertainty} from '@actql/sdk';

const state = await execution.status();
const explanation = explainEffectUncertainty(state);
// Display the unresolved Effects and physical stop separately. Any explicit
// reconciliation must use the original Client and current authority.
```

The helper performs no transport or write. Its `next` candidate is the existing
`Execution.reconcile()` operation on the original Run. The Host checks current
authority and original Effect custody when explicitly called. Inconclusive
evidence leaves the Effect outcome unknown. This candidate does not guarantee
that reconciliation will resolve the outcome, authorize resubmission, infer
rollback or assert resource release. The immutable explanation preserves what
this response reported;
later observations do not rewrite it. Copied/deserialized states, malformed
responses, other Run-state branches and user-created errors have no association
and return `undefined`. This weak association adds no Host storage, execution
ledger, provider details or public hash. An application retaining a response
or explanation retains that snapshot; no fixed retention period is imposed.

Connected Local uses a Local Host endpoint. Cloud-owned Hybrid selects at
least one registered Runner; local-owned Hybrid names its already registered
Cloud assistance connection with `cloudConnectionRef`. Both Hybrid forms
require a separate `movementPolicyRef`. The references select targets and
policies, while the Host still checks current grants and authorization.
This lightweight package does not install an embedded Local provider.

The `@actql/sdk/host-port` subpath is for the installed standard provider,
not application-side provider registration. It reuses the same Client facade
with an in-process Host port. Control values are objects, and Result reads
use typed frames rather than HTTP or JSONL. Each frame reports the bytes
transferred through that in-process Host API; the Client enforces wire and decoded-value
bounds independently. The provider must enforce its own pre-transfer row
bound, current authorization, and Run ownership before yielding a frame.
The port's `AbortSignal` belongs only to that observation or read attempt.
This boundary does not itself install a provider. The standard `@actql/node`
installation includes the lazy-loaded `@actql/local-node` provider.

`attach(ref)` retrieves another handle for the same Run. `result(name)` only
selects a named Result. Each `rows()`, `batches()` or `all()` call creates a
new delivery attempt; a reader exposes `attemptId` before iteration.
`deliveryAttempt(id)` inspects the existing Host attempt and release receipt
without sending payload. It rejects a reply bound to another attempt, Run,
Result or serialization contract, and invalid record/receipt combinations.
A reader stays `opening` until it receives the opening response (HTTPS) or
an accepted row (lazy Local frames). Failure before that observation leaves
`open_unknown`, the original `attemptId`, and zero returned rows.
`explainReadFailure(error)` preserves that opening uncertainty instead of
describing it as an authoritatively opened and stopped read. Inspect
that attempt with `deliveryAttempt(id)` before deciding on an explicit new
read. A `not_found` lookup does not prove that opening never committed, and
lookup never reopens the payload or consumes another grant use.
`explainDeliveryAttempt(lookup)` and `formatDeliveryAttempt(lookup, options)`
explain that original SDK lookup without performing another operation. They
distinguish an unresolved lookup, a recorded attempt, streaming, failed or
cancelled Delivery, and Host-confirmed success with its matching release
receipt. A copied lookup has no explanation custody. Host-confirmed bytes are
not the caller's yielded-row count, and Delivery failure/cancellation does not
fail/cancel the Run. The original read reference is retained as a read-only
lookup candidate, never permission to reopen or rerun Compute. Standard
wording is English; `locale: 'ja'` selects the existing Japanese localization.
A release receipt never proves that the Client
received or saved every value. A reader reaches `complete` only after the
normal wire terminator and transport EOF; values yielded before a failure
are a prefix. The installed HTTPS Host confirms payload termination first,
then withholds HTTP EOF until its owner durably saves the receipt and succeeded
record. Persistence failure interrupts the response and retains the original
attempt. Installed Local delivery likewise waits for the owner's terminal-record
and receipt outcome after a normal terminator.
Installed Local Host errors use the same public code policy as HTTP; private
provider causes, stacks and internal cleanup handles are not public diagnostics.
`rowsYielded()` counts complete rows returned to that reader's caller. For
`batches()` it counts rows in batches already yielded, excluding a pending
batch. Read-stream errors retain the same `attemptId` and `rowsYielded`; these
errors from `all()`, `one()` or `scalar()` report zero because the call returns
no values.
The count proves neither Run completion nor Client persistence. A fresh read
has a new attempt ID and starts from the beginning; no retry or append occurs
automatically.
An empty JSONL record fails the attempt instead of silently omitting a row.
Malformed JSON and non-object JSONL records fail as `InvalidResultFrame` before
being counted or yielded, matching the Local typed-frame boundary. Invalid row
text is not retained as a parser cause. Scalar values within object fields remain valid.

`await result.describe({format: 'jsonl'})` returns the confirmed Result's
existing Definition, Artifact and schema identifiers, declaration-ordered
columns with complete checked type contracts, and the requested delivery
profile. `jsonl` is the default; `json` and `csv` use existing delivery
contracts, while unsupported formats are rejected. No rows are sampled or
read, and an empty Result still has a description. Current authorization and
metadata retention apply on every call. Retained metadata can remain available
after payload expiration or deletion; description does not guarantee a
subsequent row read. `maxWireBytes`, `maxNodes` and `maxDepth` may tighten the
whole-response ceilings of 1 MiB, 10,000 structural nodes and depth 64.
Exceeding them fails without truncation. See
[Result description semantics](https://github.com/actql/actql/blob/main/docs/design/result-description.md).

The Client caps ordinary JSON control responses at 1 MiB of wire bytes,
including connection, submission, status, lookup and Host error bodies. Review
uses the requested body bound expanded for base64 plus a bounded envelope.
Resource inspection and peek use the requested JSON-text bound expanded for
JSON string escaping plus bounded metadata. Decoded payload limits still apply;
`Content-Length` never overrides the counted wire limit. The Client
cancels an oversized delivery without treating a submit ACK as a known
failure: `SubmissionUnknown` still carries the original request ID. This is
a Client transport bound, separate from Result read limits and from the
Host's Run resource accounting.

HTTP and installed in-process submit use the same reply admission, including
legal held requests. Explicit request, preparation, policy and admission
refusals remain known failures. Internal errors and invalid acceptance replies
are `SubmissionUnknown` with the original request ID and lookup context, even
when the in-process exception is a `ClientError`. A public-looking error code
is not by itself a refusal contract. Neither transport retries submission.

`execution.cancel({cancelId, expectedRevision, attemptId})` submits one cancellation
operation bound to the existing Run. The Host compares the expected Run-control
revision atomically on first admission. An omitted ID is generated once for
this call; an omitted revision is observed through `status()` before dispatch.
Without a control revision the SDK refuses with `CancellationRevisionUnavailable`.
For durable caller custody, choose and save the cancellation ID and expected
revision before sending. `attemptId` is a per-invocation correlation ID, generated
once when omitted; it is neither cancellation custody nor authorization.

The response contains this invocation's `attemptRef`. `accepted` and
`already_satisfied` contain the unchanged durable `cancellation` record.
`refused` certifies only that this invocation did not commit or consume an
identity; it does not rule out another concurrent invocation. `conflict` binds
the requested cancellation reference and an intent or control-revision conflict.
Only the existing Owner can issue these facts, before custody or after a
confirmed admission rollback. A generic exception or HTTP status cannot do so.

A lost, malformed or foreign response raises `CancellationUnknown` carrying
the immutable original `cancelRef`: the Run reference, cancellation ID and
expected revision, together with this invocation's `attemptRef`. Retain the original Host selection and use
`execution.lookupCancellation(error.cancelRef)` after reconnecting and
attaching that same Run. Lookup does not issue another cancellation, fence,
dispatch or Compute request. Neither submission nor lookup retries automatically.

The existing request journal retains the operation before the Model fence.
Pending custody is `unknown`; it is not accepted and absence does not establish
non-acceptance. The final operation result and Run cancellation request commit
together. A `found` lookup returns that original result even after later Run
revisions. Reusing the same ID in the same namespace and authority scope with
another target or expected revision returns an intent conflict. The bounded journal refuses
new admission at capacity and does not evict operation custody to admit it.

After a recorded outcome, `status()` separately observes the Run's
`cancellation_requested`, `physical_stop` and retained control revision.
Cancellation acceptance alone establishes no physical stop, Effect outcome or
release. A later Run flag alone does not identify the original operation.
Current authorization applies to cancellation, exact lookup and Run observation.
The separate `cancelRequest` and Checkpoint contracts below are unchanged.

The read limits use separate byte measures:

| Limit | Measure |
| --- | --- |
| `maxWireBytes` | Total received response-body bytes, including row delimiters and the normal terminator. |
| `maxRowWireBytes` | UTF-8 bytes in one JSONL row, excluding its newline. |
| `maxRowRetainedValueBytes` | One decoded row's retained-value estimate. |
| `maxRetainedValueBytes` | Sum of decoded-row estimates retained by `all()`. |
| `maxBatchRetainedValueBytes` | Sum of decoded-row estimates in one batch. |
| `maxRows`, `maxBatchRows` | Number of rows retained by `all()` or one batch. |

The retained-value estimate is JSON UTF-8 length plus 64 bytes per visited
value, property name and object entry. It is a deterministic admission bound,
not measured JavaScript heap or process RSS. Network stream chunks and runtime
overhead can make peak memory higher. An exceeded limit fails the delivery
attempt without cancelling its Run; `all()` never returns a truncated result.
The reader decodes a received transport chunk in slices no larger than 8 KiB
or the selected row wire limit, whichever is smaller.

## Original request recovery

`client.recoverRequest(observationOrTarget)` creates a lookup-only recovery
handle. It performs no I/O, submission, approval or resumption. It accepts an
original SDK submission error (`RequestHeld` or `SubmissionUnknown`), its
received Execution or successful short-query Result, or an original request
lookup response/error. Mutable error properties and copied observations do
not supply the original request context.

For an epoch-bound submission, the frozen `target` retains
`{operation: 'lookupSubmission', submissionRef: {epoch, nonce}, lookupContext: {endpoint, scopeRef}}`.
An explicit original `lookupRequest` observation retains that operation and
request ID instead. Recovery never substitutes the reconnect's epoch or falls
back to a bare nonce lookup. An application
can save this JSON and restore it with `recoverRequest(savedTarget)` after
connecting again to the same endpoint and confirmed scope. Saved targets are
untrusted lookup data, not authenticated references, durable acceptance or
permission to retry. The original epoch is retained as lookup material,
not reissued by the SDK. The SDK captures only exact own data fields
without invoking getters, `toJSON` or conversion hooks. It refuses mismatches
before lookup instead of translating an older context into a different scope.

```js
const recovery = client.recoverRequest(originalSubmissionError);
const savedTarget = JSON.stringify(recovery.target); // application-owned storage
const observation = await recovery.lookup();
if (observation.kind === 'ready' || observation.kind === 'found') {
  const execution = await recovery.attach(observation);
  const state = await execution.status();
}
// After reconnecting: client.recoverRequest(JSON.parse(savedTarget)).
```

`lookup()` returns the selected operation's existing `SubmissionLookup` or `RequestLookup` union unchanged. A held request
still has no Run; `not_found` and `unknown` do not establish nonexecution.
`attach()` accepts only a `ready` or `found` observation returned by that same handle's
`lookup()`. A direct lookup, another handle or a serialized copy does not have
that association. This local check is not authority: the ordinary Host attach
operation checks current access again. Each call is explicit; there is no
polling, automatic attachment, write retry or status-to-success inference.

The target preserves this Client's negotiated connection context; comparison
does not detect a later scope change inside a credential callback. Keep that
scope stable for the Client and create a new connection when changing it.
Current Host authorization still applies on every operation. The standard Local Host now projects its
existing root/principal/policy-bound authority scope for default as well as
explicit policy connections. Reopen the same state root and configuration;
another root with the same request ID is a different scope. Older
principal-only lookup contexts are refused, not reinterpreted. No state path,
input, credential or private review is added to the saved target.

## Historical held requests and Run Checkpoints

The initial epoch-bound standard Host path does not create pre-Run approval
waits. Delegated preparation or Source-read authorization without an immediate
permit is refused before sealing evidence or creating a Checkpoint. After
intent acceptance this is a durable preparation failure. Model and Effect
approval on an admitted Run continue through the existing Run owners.

The following bare-request operations observe historical pre-Run holds in their
original identity domain; they do not select a legacy submission path. Run
cancellation uses `execution.cancel()` and the immutable cancellation reference
returned by that operation.

An earlier Host may have held a request before any Run existed. For example, its account
configuration can delegate Run acceptance on a protected Site, and the Host
defers the decision to a durable Checkpoint. Its original `aql()` or `start()` call
rejected with `RequestHeld`. That is a control result, not a failure and not an
unknown submission. The request is stored durably, so it never needs to be
submitted again. `error.held` carries the `prepareAttemptId` and the
Checkpoint reference, and never a RunRef. Follow the request with
`lookupRequest(requestId)`. It reports `held` with the state
`waiting_checkpoint`, `resuming` or `ended` (with its reason) until the Run
exists, and then `found` with the RunRef for `attach`, `status` and `wait`.
A Program with real input can also be held before the Host reads its
source. It is the same held request, with a `read_access` Checkpoint instead
of `run_scope`; a request can be held for its run first and then for its
read. Nothing is read before the answer, and the Client still only looks the
request up.

The owner can cancel a request by its ID with `cancelRequest(requestId)`,
whether or not its Run exists yet. The reply is `accepted`,
`already_requested` or `already_terminal`. `accepted` means the Host recorded
the cancellation durably; it does not mean anything stopped or was cleaned
up. Follow the request with `lookupRequest`, which reports a held request as
`ended` with `endReason: 'cancelled'`, or with `status()` once there is a
Run. When the request already has a Run, the reply names it (`ref`) and that
Run is cancelled through its own cancellation. A lost reply or a Host
failure raises `CancellationUnknown` with the `requestId`: call
`cancelRequest` again with the same ID, and it is matched to the recorded
cancellation. Aborting the call never withdraws a recorded cancellation. A
reviewer or review reader cannot cancel.

Three operations serve reviewers. Each needs its own Host authorization:
listing, reading the review body and answering are separate permissions.

- `checkpoints({limit, after})` returns one page of waiting Checkpoints as
  safe metadata only, never review contents. `next` continues the listing.
- `reviewCheckpoint(checkpoint, {maxBytes, signal})` reads the exact review
  projection the Checkpoint names. Both sides enforce the byte bound. The
  bytes are checked against the named artifact CID, and a larger review is
  refused, never truncated. Aborting the read never cancels the request.
- `resolveCheckpoints(items, {signer})` answers one or more Checkpoints.
  Each answer is its own signed Resolution, and the Host admits each one
  separately; the batch is not atomic. `signer` is supplied by the
  application and signs with a key the Host trusts. The SDK never holds the
  key. A stored answer is not a resumed Run: the Host resumes approved
  requests itself. When the reply is lost, `ResolutionUnknown` carries the
  exact signed items. Resend them unchanged; the Host reports `duplicate`.

```js
import {createPrivateKey, sign} from 'node:crypto';
import {readFileSync} from 'node:fs';
import {connect} from '@actql/node';

const endpoint = 'https://remote-host.example/';
const owner = await connect({mode: 'remote', endpoint, token: ownerToken});
let execution;
// This ID belongs to a saved historical held request, not a new submission.
const original = await owner.lookupRequest('nightly-1');
if (original.kind !== 'held') throw new Error('HistoricalRequestNotHeld');

// Later, from any process: review and answer.
const reviewer = await connect({mode: 'remote', endpoint,
  token: reviewerToken});
const {items: [checkpoint]} = await reviewer.checkpoints();
const reader = await connect({mode: 'remote', endpoint, token: readerToken});
const review = await reader.reviewCheckpoint(checkpoint, {maxBytes: 65536});
const key = createPrivateKey(readFileSync('reviewer.key', 'utf8'));
const {results} = await reviewer.resolveCheckpoints(
  [{checkpoint, decision: 'approved'}],
  {signer: {keyId: 'reviewer-key', reviewerId: 'reviewer',
    sign: bytes => sign(null, bytes, key)}});

// The Host resumes the request; follow it to its Run and Result.
const lookup = await owner.lookupRequest('nightly-1');
if (lookup.kind === 'found') {
  execution = await owner.attach(lookup.ref);
  const rows = await execution.result('answer').all();
}
```

## Unknown Effect outcomes

A Run whose Effect writes may have reached the provider without a known
outcome is never reported as succeeded or failed. `status()` reports
`needs_reconciliation`, and `next_action` is `{kind: 'reconcile', effects}`
naming exactly the Effects whose outcome is unknown. `reconcile()` returns the
Run's current state after the Host's reconciliation attempt. Neither call
resends a write, and a restarted Host reports the same state for the same
request. Submitting the same request again returns the existing Run.

## Resource discovery

`resources(resourceConnection, {query, limit})` lists the Resources a Host
that serves discovery for that connection shows to the caller, from the Host's current Catalog
observation. `snapshotComplete`, `snapshotTruncated` and `resultTruncated` say
whether the listing is the whole Catalog; a missing name is not evidence that
a Resource is absent. `inspectResource(resourceConnection, resource)` returns
typed metadata, or `catalog_required` with a reason when the Catalog cannot
answer yet. Neither call reads business rows or grants reading or running
anything.

A Resource the caller is not currently allowed to read is refused
(`ResourceDiscoveryDenied`) and is left out of `resources`: nothing tells
whether it exists. For a Resource the caller may read, the reasons are:

| State | Listing `outcome` | Inspect `reason` |
| --- | --- | --- |
| Outside a targeted (published) observation: not checked | not listed | `not_observed` |
| An authorized describe answered not found for this principal | `not_found` | `not_found` |
| The describe failed or the provider refused it: state unknown | the failure, e.g. `permission_denied` | `describe_unavailable` |
| A provider listing was cut off by its limits | not listed | `listing_truncated` |
| A complete listing did not include it | not listed | `not_visible` |

A provider permission failure is never reported as `not_found`, and
`not_found` holds only for this principal at the time of the observation.

`peekResource(resourceConnection, resource, {fields, maxRows, maxBytes})` is
authorized separately. It returns at most `maxRows` rows with exactly the
requested `fields`; `limited` is true when the reply reached `maxRows`, so
more rows may exist. Row order is not part of the reply. A preview is display material,
never a complete read, Acquisition evidence or a Result.

```js
const listing = await client.resources('salesforce:00D000000000001EAA',
  {query: 'record'});
const preview = await client.peekResource('salesforce:00D000000000001EAA',
  'Test_Record__c', {fields: ['Id', 'Name'], maxRows: 5});
```

## Query text and machine input

`aql-text` accepts the implemented query language, including Pipe and admitted
Graph patterns; `sql` selects SQL query heads. The retired
`AQL / PROGRAM / STAGE / STEP / OP` envelope is rejected by the Host before
Run acceptance and provider I/O. JSON/YAML Program remains supported machine
input. Text is never retried as another format, and extensions do not choose
a language. Removal of the old surface does not claim that every adopted
Graph, VecA/TEA or Effect surface is implemented.


## Checking authored input

Every `client.check` call selects `kind: 'text'` or `kind: 'program'` and
`scope: 'template_only'` or `scope: 'bound_input'`. Omitting either selection is
an invalid check request. The Program overload receives a JSON object snapshot
and reports JSON pointers; it does not manufacture source-text positions.

```js
const template = await client.check('SELECT @x AS n', {
  kind: 'text', scope: 'template_only', format: 'sql',
  parameterDeclarations: {x: {type: 'number'}},
});
const programTemplate = await client.check(program, {
  kind: 'program', scope: 'template_only',
});
const complemented = await client.check('SELECT @x AS n', {
  kind: 'text', scope: 'bound_input', format: 'sql',
  parameterDeclarations: {x: {type: 'number'}}, parameters: {x: 1},
});
```

Template-only requests cannot contain `parameters`, including `null`, `{}` or
an explicitly present `undefined`. The SDK and Host refuse these requests;
this refusal is distinct from an invalid Program. Declaration defaults retain
their existing admission rules. Template verification requires complete common
static-scope evidence; it may retain execution-value Requirements. Missing
bound values, incomplete static checks and truncated reports cannot verify.
Complementing inputs starts a new bound-input check. Checking and retrieving
diagnostics do not submit a Program or grant permission to execute or resend it.

```js
import {getCheckInput, resolveCheckLocation, explainCheckReason, explainCheckOutcome} from '@actql/sdk';

const outcome = await client.check('SELECT @missing AS n', {kind: 'text', scope: 'bound_input', format: 'sql'});
console.log(explainCheckOutcome(outcome));
if (outcome.outcome === 'completed') {
  const {scope, context_ref, verdict, reasons, requirements} = outcome.report;
  for (const reason of [...reasons, ...requirements]) {
    const explanation = explainCheckReason(reason);
    const location = reason.location && resolveCheckLocation(outcome, reason.location);
    // location.input belongs to this submitted revision, including while editing.
    console.log({scope, context_ref, verdict, explanation, location});
  }
  const submitted = getCheckInput(outcome, 'source');
}
```

`explainCheckOutcome(value)` validates the existing public envelope and describes
its reported branch. A completed explanation keeps the verdict together with
scope, context reference and `completeness: 'complete'`. A failed explanation
keeps any bound partial report explicitly partial; it cannot verify. An
unavailable explanation contains a correlation reference and no report or
verdict. Unknown problem codes retain their branch with a generic explanation;
malformed envelopes and unsupported variants return `undefined`.

Analysis exhaustion may still produce a completed, undetermined report. Failure
to construct the bounded report instead produces `failed` with
`check_report_unbounded`; its hint asks the checking-context owner to review
reporting capacity for the original scope. Neither describes an input violation.
Verification describes checking only; execution, cancellation and release have
their own owners and results.

This formatter can describe a schema-valid parsed copy without the original
input. It does not authenticate that copy, restore locations, apply edits or
authorize another operation. Location helpers still require the exact SDK
response and its original submitted snapshot. Explanations are immutable, safe
English text; they do not expose private causes or inspect error messages.

Before credentials or transport, `check` rejects non-finite numbers and negative
zero in supplied parameters or declarations (including nested values, boxed
Numbers and values returned by `toJSON`) with `InvalidCheckRequest`. Public
Local/HTTPS ingress independently refuses these values as `InvalidClientRequest`
before invoking check, including overflowing HTTPS numeric tokens. Local owns
its detached request before awaiting authentication. JSON serialization must not replace these numbers with
`null` or zero and check a different input. This is request admission, not an
`invalid`, `verified` or `undetermined` checker verdict.

A completed check may be invalid or undetermined. Its verdict is always bound to
scope/context and does not start or authorize a Run. Wrong supplied types expose
expected/actual types without values. Missing declared values expose Requirements
and remain undetermined in bound-input scope. Unsupported checking and budget
exhaustion are not author errors. Inaccessible and absent installed Source aliases
share unresolved coverage; an independent public violation remains visible.

`getCheckRequirementFrontier(outcome)` retains the known public parameter
Requirements of this exact completed SDK response. Each typed requirement also
retains its optional `facts.admission` as `CheckParameterAdmission`, including
the checked contract, constraints and supplying role. This is the same disclosed
condition shape returned by `getCheckParameterAdmission`; it adds no validation
or execution permission. `equalCheckRequirementFrontiers(a, b)`
compares their bound scope, opaque context reference, reason schema, typed
obligation set and outstanding coverage. Requirement order, duplicates, fact-key
order and optional presentation locations do not establish progress. Changed
bindings or declarations change the bound context even when the remaining
parameter names and expected types are identical. The returned observation is
immutable; copied or partial reports are not comparable. The current closed
wire schema rejects unknown Requirement codes and malformed known facts.

```js
import {createCheckSupplementationSession} from '@actql/sdk';
const checks = createCheckSupplementationSession(client, {maxAttempts: 3});
const result = await checks.check('SELECT @x AS n', {
  kind: 'text', scope: 'bound_input', format: 'sql', parameterDeclarations: {x: {type: 'number'}}, parameters: {},
});
// Present the unchanged Owner outcome, including its scope and verdict.
console.log(result.outcome, result.decision);
// After obtaining a value, explicitly call checks.check with the new bindings.
```

The session issues only the caller's explicit read-only checks. It stops after
an unchanged frontier, a non-comparable response, no known supplementation path,
or the total attempt cap, including across changing contexts. Failed attempts
consume that cap; concurrent calls refuse before another attempt. A stopped
session refuses further calls before transport I/O. `more_checks` indicates
remaining local attempt capacity, not verification, progress, permission to
execute or authority to write supplements. Per-call Owner analysis/reporting
budgets still apply; the session does not measure total server work. It creates
no submission lifecycle, Host input storage, public hash or new wire contract.

The SDK captures response fields once before checking their branch or contract.
Validation, copied-value comparison and input binding use the same owned facts;
a getter cannot replace its first value between admission and copying. The
first capture supplies the returned observation and its explanation; the later
verification copy cannot change them after validation. A conversion that changes the original captured data is also refused before binding or return.
This also applies to submission, request lookup/cancellation, Run observations and
cancellation, and DeliveryAttempt lookup. Throwing getters produce the safe
operation-specific failure without retaining the exception. Request serialization
remains separate. Run responses remain mutable while private explanations retain
immutable admitted facts.

The SDK then binds input snapshots and freezes the check observation. A Local
Host can reuse its response objects; later replies cannot replace an earlier outcome, context, input or
location association. Completed and failed partial reports keep their own
submitted inputs. Unavailable responses provide no bound report or snapshot.
Uncapturable response data or replies whose verification copy fails or violates the wire contract
fail with `InvalidHostCheckOutcome` before acquiring an input association.

Locations use the immutable original input snapshot, not the latest editor buffer.
`resolveCheckLocation` returns `undefined` for a copied report, missing snapshot,
stale revision, changed content, invalid byte boundary or a structured pointer
without a submitted JSON node. Supplying its optional
current-input argument validates the same identity/revision/content. Text spans
are UTF-8 byte intervals; structured values/declarations have revision-bound
pointers. Pointer resolution uses only owned object members and canonical array
indices, preserving the submitted member spelling and RFC 6901 escape order.
Inherited properties, array metadata, missing nodes and scalar descendants
cannot identify submitted nodes. Invalid Host locations refuse the check with
`InvalidHostCheckOutcome`, including locations in partial reports or Requirements.
There is no SDK parser, automatic fix or Host input re-fetch API.
Typed expression failures use `query_expression_invalid`, with `facts.issue`
`unknown_reference`, `invalid_arguments` or `invalid_number`. They identify an
unresolved expression reference, invalid operation arguments or the admitted
numeric domain, respectively. Numeric domain failures differ from the lexical
reason's numeric spelling failure. `explainCheckReason` supplies safe summaries
and advisory correction hints; messages do not determine verdicts. Only existing
authored origins supply reference, call or numeric ranges. Missing/generated
origins and protected Source resolution acquire no fabricated span or name.
The existing lowerer's `UnknownColumn` also supplies `unknown_reference` facts,
including bare column selections. It currently has no retained authored origin,
so its location is omitted; adding an alias may expose an existing exact origin.
The SDK uses the same submitted snapshot for syntax and expression ranges.
`resolveCheckTextRange(outcome, location, currentInput?)` additionally returns
zero-based `range.start`/`range.end` line and character coordinates with
`positionEncoding: 'utf-16'`. It reads that same immutable source snapshot and
preserves the location's `precision`. BOM and combining marks count as UTF-16
code units, non-BMP characters count as two, and CRLF is one line break; lone CR
and LF also start a line. EOF and zero-width locations are supported. A boundary
inside CRLF or malformed original Unicode has no exact editor range and is
omitted. Structured locations remain pointers, without fabricated text ranges.
`resolveCheckTextRangeEncoding(outcome, location, encoding, currentInput?)` uses
that same walker with an already negotiated `utf-8`, `utf-16` or `utf-32`
encoding. UTF-8 columns count bytes, UTF-16 columns count code units and UTF-32
columns count Unicode scalars. Unsupported encodings are refused. Neither helper
negotiates a protocol or applies edits; approximate ranges retain their label.

`createCheckDocumentSession(client, {text, version, positionEncoding?})` binds one
open unsaved buffer to explicit SDK checks. The default encoding is UTF-16, as in
[LSP's position contract](https://github.com/microsoft/vscode-languageserver-node/blob/main/types/src/main.ts).
`update(text, version)` replaces the entire buffer only with a well-formed string
and a strictly increasing signed 32-bit version. Negative initial versions and
nonconsecutive increases are allowed. Undo/redo still advances the version.
Reopening requires a new session. The session does not infer text from a URI.

```js
const document = createCheckDocumentSession(client, {text: buffer, version: 1});
const observation = await document.check({scope: 'bound_input', format: 'sql'});
const report = observation.outcome.report ?? observation.outcome.partial_report;
for (const reason of report?.reasons ?? []) {
  const range = reason.location && document.resolveTextRange(observation, reason.location);
  // Display the safe reason even when no current editor range is available.
}
document.close();
```

Each check captures the current text/version before waiting. Position resolution
requires the original observation from this session, the current version and
exact bytes, and the newest issued check. A newer pending or failed check also
invalidates earlier positions, including checks with unchanged text but different
bindings/context. Reordered replies remain historical observations; editing,
closing, reopening, foreign sessions and copied observations cannot rebind them.
A response without SDK-owned source input has no editor range. Safe explanations
remain available through `observation.outcome` independently of position display.

A session retains one current buffer and its shared Client while open. Outstanding
checks retain their captured input until settlement; retained original outcomes
keep their existing SDK input snapshots through weak associations. Session
observation associations are also weak and do not retain an independent history.
`close()` drops the current buffer and Client reference and invalidates all editor
positions; it neither cancels outstanding checks nor closes the shared Client.
The session has no additional buffer byte cap or timed retention; explicit check
calls still use the existing SDK/Host request admission bounds. No extra Host
persistence, retrieval API, public input hash or retention period is introduced. This is an SDK document adapter, not a full LSP server or a fix
application mechanism.
Nested object/array type failures identify the declared child type and the
existing binder's path, with JSON pointer escaping for field names. Supplied
constraint violations with an owned binder cause expose
`supplied_value_constraint_violation`, a safe parameter name and a typed family:
`numeric`, `duration`, `array_length` or `array_size`. They can carry the same
owned path. Numeric means the admitted integer/minimum/maximum constraints;
the reason does not claim which one failed. `explainCheckReason` provides a
family-specific hint. The declaration snapshot is available through
`getCheckInput(outcome, 'parameter_declarations')`; actual values are not facts.
Other violations remain safely generic rather than guessing a cause.
JSON parser failures in supplied values and declarations can also carry the
original structural path before a decoded cursor exists. The existing preserving
JSON reader supplies location material only when its typed failure and source
position match the authoritative parser failure; it never changes the verdict.
These retain
`supplied_parameters_invalid` / `parameter_declarations_invalid`; the pointer
belongs to the corresponding submitted input revision. Escaped unpaired
surrogates identify the original value; an undecodable member name identifies
the parser's known enclosing container. Unknown paths stay absent, and parser
budgets remain checking limits without an input-violation location.
Missing submitted nodes and pointers beyond the public bound have no location;
invalid defaults never point into supplied values. Values remain in the local
submitted snapshot, not in public diagnostic facts.

Typed lexical failures use `query_lexical_invalid` with `facts.issue`, one of
`unexpected_end`, `unexpected_token`, `invalid_escape`, `invalid_scalar`,
`empty_identifier`, `unterminated_comment`, `invalid_number` or
`invalid_parameter`. `explainCheckReason` provides an issue-specific safe
summary and hint. A location, when available, uses the parser's original source
position, including exact zero-width positions. It contains no token text or
private parser message. Ordinary grammar failures retain
`query_syntax_invalid`. Budget limits remain undetermined coverage rather than
lexical invalidity. Hints are advisory and never apply an edit or confer authority.

`getCheckFixes(outcome)` returns the typed proposals associated with that exact
completed SDK response; copied or externally parsed reports return `undefined`.
For the existing lexer's `unterminated_comment` issue with an exact original
position, the Host offers `close_block_comment`: insert literal `*/` at the
original source's EOF, bound to its document revision. It declares
`applicability: "requires_review"` and `risk: "syntax_structure"`. Other issues,
unresolved protected dependencies and inexact origins acquire no fabricated fix.

An open `createCheckDocumentSession` can apply explicitly selected proposals with
`await session.applyFixes(observation, fixes, {version: 2, reviewed: true})`.
The new version must increase. Only proposals from the latest check of that
unchanged session are eligible. Copied proposals, stale revisions, duplicate
insertion points and conflicting edits are refused without changing the buffer.
The SDK reuses the original format and detached bindings. It checks the original
request's current context, checks the staged edited text, then checks the original
context again before committing the one-document edit and its new observation
together. A failed/unavailable recheck, concurrent edit/close/new check, or observed
permission/context change leaves the buffer unchanged. The returned observation
contains the actual recheck verdict, including remaining violations; applying a
proposal never implies verification. Context checks are observations, not a
remote authorization lease. No Run or external Effect is executed.

The request snapshot remains weakly associated with the response for this reuse;
retaining the response retains its original source and bindings. Closing a session
drops its current buffer and Client reference. Host processing adds no durable
storage, refetch API or retention-period promise. Existing request/report limits
still apply. This extension changes the reason/outcome schema bodies and pins;
preceding SDK/Host pins reject each other explicitly. Legacy diagnostics remain
separate and no compatibility implementation is retained.

This coordinated correction changes the closed `actql-check-outcome/0.1` schema
and introduces `actql-check-reason/0.1`. Schema identity, validator and SDK/Host
must match; a mismatched reply throws `InvalidHostCheckOutcome` and never becomes
success or an empty diagnostic report. Existing `actql-diagnostics/0.1` is a
separate contract. Original snapshots remain weakly associated with the response;
retaining a response or a retrieved snapshot retains its submitted input.


### Predicate type explanations

The registered `query_expression_invalid` reason also carries
`facts.issue: "expected_boolean"` for the common Relation checker's
`ExpectedBoolean` rejection. The SDK explains that a predicate requires Boolean
type and suggests a Boolean condition such as a comparison. It does not reveal
the submitted value or invent an actual type absent from the retained issue.

The checker-facing span does not retain authored/generated provenance, so this
projection omits the location. A lowered Program path is not an original SQL
position. Absent and inaccessible Source dependencies stop before dependent
predicate checking and retain equivalent protected unresolved coverage.
The verdict still comes from the common checker; explanations are advisory.

### Parameter default type explanations

`parameter_default_type_mismatch` explains the declaration owner's typed
wrong-type or unexpected-null rejection of a literal default. Its closed
`parameter`, `expected_type` and `actual_type` facts describe the failing leaf,
including nested object fields and array items; they contain no default value.
Its optional structured location belongs to `parameter_declarations`, uses the
original key spelling and binds to the revision retained for that check call.
The SDK advises correcting the default rather than supplying a missing value.
A valid default still goes through the common checker. Declaring an unused
parameter is independently invalid; a default is not a parameter use.

Other declaration errors keep their existing safe fallback. Declaration budgets
remain analysis limits. No dependent Source diagnosis is inferred after
rejected declaration admission. The Host adds no persistent input storage or
retrieval API, and the SDK retains the existing call-bound input custody.

This extension changes the registered `actql-check-reason/0.1` body and reason CID
with coordinated Host, schema, validator, SDK type and fixture updates. The embedded reason pin also changes the `actql-check-outcome/0.1` schema body
and CID; the outcome fields and verdict semantics remain unchanged.
`actql-diagnostics/0.1` remains unchanged.
Mixed reason-schema pins are rejected; there is no compatibility adapter.

### Graph argument explanations

The public `graph_operation_invalid` reason carries closed facts
`operation: "components"` and `issue: "invalid_kind"` or
`"invalid_output_rows"`. These facts project existing common Graph checker
`InvalidBody` at `components.kind` and `InvalidCount` at
`components.max_output_rows`; they do not introduce a second checker.
The SDK explains the required weak/strong kind or positive safe integer row
limit. Other Graph failures retain their existing classification and safe
fallback. Neither the submitted value nor an internal Program path is exposed.

Graph lowering assigns the authored call range to its diagnostic body, while
the checker-facing span does not retain the authored/generated origin kind or
individual argument precision. This projection omits locations until that
owned provenance is available to the public consumer; an internal Program
path is not an input location. Absent and
inaccessible Source dependencies stop before this dependent Graph diagnosis
and retain the same protected unresolved result. Source-free valid weak and
strong components remain verified. Checking does not execute a Graph task.

Subgraph selector violations carry `operation: "subgraph"` and
`issue: "invalid_node_selector"`. The SDK describes the closed selector forms:
nonempty ids, a named Relation with an id field, or a node where predicate.
The currently unimplemented where form is an implementation limit with an
undetermined verdict. Invalid selectors are input violations. Generated
Program paths are not authored locations, so these explanations omit positions.
Protected dependencies suppress dependent Graph explanations while independent
supplied-value violations remain public.

This coordinated extension changes the registered `actql-check-reason/0.1`
body, its identity pins, validators and SDK wire types. The Subgraph extension
changes the reason-schema CID and the outcome-schema CID because the latter
embeds the exact reason pin. Outcome fields and verdict semantics remain unchanged.
It leaves `actql-diagnostics/0.1` unchanged. Mixed schema pins are rejected by
existing contract validation; there is no compatibility adapter.

### Run cancellation explanations

`explainCancellation(result)` returns immutable read-only advice for the exact
response or uncertain error produced by this SDK's `Execution.cancel()` or
`Execution.lookupCancellation()` call.
The SDK detaches each validated cancellation response, so a Local port reusing
its response object cannot change an earlier result's Run, kind, revision or
explanation.
The detached value is revalidated against the response schema, original Run,
cancellation ID and expected revision. Clone failures or changed fields raise
`CancellationUnknown` with the original operation's `outcome_unknown` advice;
they never trigger another cancellation request.
Validated `accepted`, `already_requested` and `already_terminal` observations
retain the Host's control revision. The summary distinguishes recording a
cancellation request, an existing request and a Run already terminal for
cancellation. Each provides a `status` target for the same retained Run
reference. Cancellation acceptance establishes no physical-stop, external
Effect outcome or resource-release fact.

Transport loss, malformed replies and differently bound replies retain an
`outcome_unknown` explanation without a fabricated recorded revision. Its
`next` names `lookupCancellation` and the immutable original `cancelRef`.
An HTTP `Response` object returned through Local is also an invalid
representation with an unknown cancellation outcome. Changing
an error code/message or a returned response after the call does not change
its bound explanation. Handwritten, parsed or copied objects have no SDK
association. For the cancellation write, local failures before dispatch retain their errors.
Typed `refused` and `conflict` results remain structured Owner facts without a
fabricated recorded cancellation observation.
The accessor performs no I/O or automatic retry and retains no provider cause.
The presentation association lasts only while its SDK result is retained.

An exact lookup captures all five original reference fields before validation,
copy verification or asynchronous transport. Changed copies are rejected before
lookup dispatch. A validated `found` lookup explains its retained cancellation
kind and recorded control revision, independently of today's Run status. An
`unknown` lookup, lost reply, denied lookup or malformed reply retains only the
original read-only `lookupCancellation` target; none establishes nonacceptance
or physical stop. `formatCancellation(lookup)` uses that same owned observation.
Editing the caller's reference or reusing a Host reply cannot rewrite an earlier
explanation. Looking up or formatting never sends another cancellation.
The Host's separate durable operation custody is owned by its existing journal.

The typed attempt envelope reuses the existing journal's cancellation identity
and immutable outcome. It does not add a cancellation ledger or rewrite old
records. Exact lookup remains the original operation's contract and is
independent of the latest invocation or current Run status. The Submit typed
attempt and multi-owner observation have separate identities and contracts.


### Unused Parameter explanations

`parameter_unused` projects the common checker's typed `UnusedParameter`
rejection after complete Program checking. Its closed facts contain only the
caller-owned declaration name. The SDK suggests removing the declaration or
referencing the parameter, rather than supplying another value.

The optional structured location belongs to the original submitted
`parameter_declarations` map and its call-bound revision. Lowering copies
these declarations into generated Program cursors; those copied paths are
never exposed as original input locations. Original names are admitted ASCII
identifiers. Unknown provenance omits a location, and an oversized name retains
the safe `program_invalid` fallback. No default, supplied value or Source
identity is added to the explanation. A copied response has no original-input
custody; a missing or different revision cannot resolve a location.

This does not independently scan for parameter references. Missing bindings,
protected Source dependencies, unsupported operations and analysis budgets
retain the existing common checker's classifications. They do not acquire an
unused-declaration verdict before that Owner reaches the usage decision.

The coordinated extension changes the `actql-check-reason/0.1` schema body,
reason CID and the `actql-check-outcome/0.1` schema CID that embeds it. Host,
validators, generated wire types, SDK and independent fixtures are updated
together; mixed pins are rejected. `actql-diagnostics/0.1` remains unchanged.
There is no compatibility adapter, new parser, Host input persistence or
retrieval API. Existing per-call input custody and destruction conditions apply.

### Check explanation language

Use `explainCheckOutcome(outcome, {locale: 'ja'})` or
`explainCheckReason(reason, {locale: 'ja'})` for Japanese check presentation.
`ja-JP` selects the same translations. English remains the default; unknown
locale names, failed locale lookup and missing/malformed translations fall
back to safe English. `getCheckPresentationInfo({locale: 'ja'})` identifies
the selected translation revision separately from the pinned reason/outcome
schema identities.

Only summary and hint change. The received verdict, scope/context, Problem
correlation, typed facts, input revision/position binding and Requirement
frontier remain unchanged. Rendering performs no transport or Owner action;
translated hints do not authorize execution, cancellation, retry or recovery.
Malformed outcome envelopes do not gain a usable outcome explanation through translation.
Copied responses retain safe wording without reconstructing original input.


### Interrupted read explanations

`explainReadFailure(error)` returns immutable SDK-observed progress for the original
read error. It includes the read reference, `rowsYielded`, and the original
connection, Run and named Result target for `result.deliveryAttempt(attemptId)`.
Copies and independently constructed errors have no retained explanation. Changing
an error's message, code or public properties does not replace the observation.
The explanation keeps no returned row values or credentials.

For `rows()`, the count is complete rows yielded by that reader. For `batches()`, it
counts rows in batches yielded to the caller, excluding an unfinished buffered
batch. A failed `all()` returns no value and reports zero caller-yielded rows.
These counts do not establish server-sent or application-persisted rows. A read
failure can also retain `cleanup: 'unknown'` when cancellation of that reader
separately failed; wrapping the reader does not erase either observation.

The lookup suggestion performs no I/O and grants no retry permission. Use the
original Client/Result and current authorization to inspect the attempt. An absent
record does not prove that opening was never committed. If the caller explicitly
opens another read after checking availability, it starts from the beginning;
it does not append to or resume the interrupted iterator. Read interruption or
cleanup uncertainty proves neither Run failure, Result publication nor resource
release.


`formatCheckOutcome(outcome, {format: 'text' | 'html' | 'json', locale?, maxBytes?, currentInputs?, positionEncoding?})`
formats the validated public check observation for terminal output, HTML display,
or structured agent data. Text is the default. It delegates summaries to the
existing explanation helpers and preserves the Owner verdict, scope, completeness
and context. Agent JSON keeps reason/outcome schema CIDs separately from the
selected translation revision. Requirements, limits and protected unresolved boundaries stay distinct
from violations. Unknown reasons have generic explanations; malformed known facts,
wrong schema identities and unknown outcomes return `undefined`.

HTML escapes markup. All formats escape untrusted control and bidirectional marks;
agent JSON also escapes markup delimiters while preserving string data on parse.
The output contains disclosed typed facts and locations, never original input text,
parameter values, private causes, provider debug links, executable actions or input access. It performs no
transport, checking, edit, submission or retry. Render HTML as this complete
fragment; do not reinterpret its escaped strings as markup.

Locations require the exact SDK response's original input association. Copied
reports still display safe explanations but omit positions. For a current editor,
pass `currentInputs` explicitly: missing, edited or stale revisions omit positions.
Matching current inputs validate freshness; resolved locations use the SDK-owned
immutable submitted snapshot, so later reads cannot switch to caller-mutated text.
An absent option displays coordinates of the submitted revision only, never an
assumed latest editor buffer. Text locations include original UTF-8 offsets and,
when representable, the existing UTF-16 range. Structured pointers remain separate.
This is display plumbing, not an LSP document-session owner or a fix applicator.

The default output limit is 65,536 UTF-8 bytes; `maxBytes` must be an integer from
1,024 through 1,048,576. Whole entries are retained in report order until the bound
is reached. `omittedEntries` in JSON and an explicit omission line in text/HTML
report the remaining count. Truncation never changes the observation or claims
complete diagnostic display. If even the observation cannot fit, return
`undefined`; callers retain the original typed outcome for another display.


```js
import {formatCheckOutcome} from '@actql/sdk';
const outcome = await client.check(text, {kind: 'text', scope: 'bound_input', format: 'sql'});
const display = formatCheckOutcome(outcome, {format: 'text'});
if (display === undefined) throw new Error('CheckDisplayUnavailable');
console.log(display);
```

`positionEncoding` selects the already negotiated `utf-8`, `utf-16` or `utf-32`
text coordinates. UTF-16 is the default; an unknown encoding refuses the display.
The formatter reuses the SDK's original-byte coordinate conversion. Structured
input pointers stay structured locations and have no text encoding.

For an open unsaved document, `session.format(observation, options?)` uses the
session's negotiated encoding and the same current-observation gate as
`session.resolveTextRange`. It keeps safe explanations, facts, verdict and the
original context for old, closed, foreign or copied observations, while omitting
their positions. A newer pending check invalidates older positions even when
the text and document version are equal. It reads application options before
checking currency and checks again after rendering, because a supplied input
accessor can edit or close the session. An explicitly supplied current-input set
is respected; malformed or missing current entries do not restore older positions.
The session retains no additional input, sends no request for formatting and
applies no edit.

```js
const session = createCheckDocumentSession(client, {
  text: unsavedText, version: documentVersion, positionEncoding: 'utf-8',
});
const observation = await session.check({scope: 'bound_input', format: 'sql'});
const display = session.format(observation, {format: 'json'});
// Call session.update(newText, newVersion) for edits and session.close() on close.
```

`binding_json_invalid` explains the existing parser's failure to admit submitted
parameter declarations or values. Closed `facts.document` identifies which
original input failed, and `facts.issue` identifies the parser family without
including member names, values or messages. Unicode scalar failures and member
names that collide under the admitted normalization rules are distinct. Exact
owned structured pointers remain optional; a location recovery read cannot
substitute another issue. Budgets are checking limits, not invalid JSON. Correct
the submitted input and explicitly check again; these hints apply no edit and
grant no execution authority.


The operation explanation helpers `explainSubmission`, `explainCancellation`,
`explainReadFailure` and `explainEffectUncertainty` accept optional `{locale}`
with the same `en` / `ja` / `ja-JP` selection as check presentation. Unknown
selections or a throwing locale getter retain the safe English explanation.
`getOperationPresentationInfo({locale})` returns the operation translation
revision; it is separate from the check translation revision, schema CIDs and
Program/Run/Result identity.

The helpers first retrieve the original immutable SDK observation, then choose
wording. Locale changes preserve every observation, request/Run/read reference,
control revision, physical-stop fact, cleanup fact and caller-yielded row count.
They perform no lookup, submit, cancellation, reconciliation or read. Changing
an error or response while the locale getter runs cannot replace retained facts;
copies and foreign objects still have no retained explanation. English keeps
the original frozen explanation; translated results are frozen and reuse its
immutable nested data. No source, value or credential retention is added.

```js
const explanation = explainCancellation(cancelReply, {locale: 'ja'});
// Cancellation acceptance still requires a fresh status for stop and release.
const presentation = getOperationPresentationInfo({locale: 'ja'});
```

A held request is distinct from uncertain acceptance and from a received Run
reference. A reader interruption reports only rows returned to that caller;
it does not establish publication or execution success. Uncertain reader cleanup
stays uncertain. An unresolved Effect stays unresolved even when computation
stop is separately confirmed. Translation cannot grant retry or reconciliation
permission; inspect the original Owner through the retained reference and current
authorization when the caller explicitly chooses to do so.

When response decoding, schema admission or original-input binding fails,
`client.check` still rejects with `InvalidHostCheckOutcome`.
`explainCheckFailure(error, {locale})` explains only the original error produced
by that SDK call. It distinguishes `uninterpretable/unknown_outcome` from
`protocol_failure/malformed_response` and `protocol_failure/contract_mismatch`.
A valid unknown reason code continues to use `explainCheckReason`'s safe unknown
explanation; malformed facts for a known reason never become a valid unknown
reason. These failure explanations contain no verdict, scope, location,
correlation reference or retry instruction. They perform no I/O.

`getCheckFailureInput(error)` explicitly returns the detached submitted text,
format, declarations and parameter snapshot for that call. It adds no document
revision and cannot resolve positions or apply fixes. Copied, serialized and
foreign errors cannot recover the snapshot. Error serialization and explanation
omit both the original input and all rejected Host payload fields. Input stays
in memory through a weak association to the error; retaining the error retains
that input. The SDK imposes the existing check-request admission limits, adds no
persistent storage, and promises no timed retention or destruction interval.


### Located function-lowering limits

The existing lowerer's UnsupportedFunction conflates unknown names, quoted or
qualified forms and implementation gaps. Public checking keeps implementation_limit
in coverage and never infers author blame from that issue. Its optional closed
facts identify function_lowering_unresolved, with an existing original Authored
call range. The generic code-only limit and its required payload remain unchanged.

The bridge consumes the typed origin directly. Unknown/generated origins remain
unlocated; no text search, second parser, rerun resolution or lowered JSON path
supplies an SQL position. Exact original source revisions/UTF-8 ranges survive
Local/HTTPS and SDK, including repeated names/comments, non-BMP/combining text and
CRLF. Located coverage limits receive the same revision, bounds and UTF-8-boundary
admission as violations/Requirements; malformed transported material is a protocol
failure. No fix or operation permission follows from this support limit.

A protected relation can stop lowering before a dependent function issue exists.
It cannot manufacture a function fact or position. Public violations still survive;
unsupported-only checks remain undetermined. Reason/Outcome schema bodies, pins,
producer, validators, generated types, SDK and independent fixtures change together.
Legacy diagnostics and unrelated schema bodies remain separate. No compatibility
path, new source custody, retention or lowerer implementation is introduced.
### Bounded known Requirement enumeration

A completed check may include `report.omissions: {requirements: true}` when the
reserved reporting budget omits known input requirements. Its verdict and
bound-input scope still account for the full originally submitted input; the
flag is not a new analysis limit or a verified partial report. Safe violations
and protected coverage remain in the report. No omitted count is exposed.
Absence of the flag means this known Requirement enumeration was not truncated.

`explainCheckOutcome` retains that flag separately from operation completeness.
Text/HTML displays mark Host omissions; JSON retains the typed flag. Renderer
`omittedEntries` counts only disclosed entries that its own display budget
omits, and cannot estimate Host omissions. `getCheckRequirementFrontier` refuses
truncated enumeration, so a check supplementation session stops rather than
mistaking a prefix for a complete admission frontier. A valid old report remains
bound to its original input/context; no more checking or supplementation is
performed by presentation.


### Declared parameter admission conditions

A known missing-parameter Requirement can include `facts.admission`. This
closed `parameter_declaration` representation is emitted from the existing
admitted `ParameterType` Owner: its complete checked value contract,
parameter-only numeric/integer, duration and exact-array-length rules, and
`supplier: "caller"`. The checked-contract schema CID is pinned in the facts
schema, so changing that referenced schema changes the Reason/Outcome identities.
Defaults, annotation metadata and supplied values are never projected here.

Rule paths use typed `field` and `items` segments of a type definition. They are
not source positions or supplied-array indices. The Requirement's separate
structured location still binds the caller's original declaration document and
revision. Nullability, object fields, array maxima and decimal precision/scale
come from the checked contract; parameter-only constraints retain their own
rules. Conditions describe declaration admission, not all later operations or
complete Program verification. An absent optional admission object means those
expanded conditions are not available in that public Reason; no unconstrained
fallback is invented.

`getCheckParameterAdmission(outcome, name)` returns conditions only for that
call's original SDK-owned completed response and a disclosed Requirement.
Copies, forged responses, omitted Requirements and supplied values return
undefined. The data is immutable and confers no input-write, approval or Run
permission. Actual supplied values re-enter the existing binder and checker.
The original unbound report remains bound to its earlier context.

Constraint-row order is not supplementation progress; the existing frontier
comparison uses its unordered typed set while preserving the semantic order of
segments within each path. Context changes still consume the total attempt cap.
If the reserved report budget cannot encode a whole Requirement's conditions,
the existing omissions marker preserves the complete bound verdict/scope and
prevents an incomplete frontier. Analysis is not repeated.

`NeedsInputs` remains a partial checking frontier. Preparing declaration types,
Stage topology or an unbound result wiring cannot certify all remaining static
obligations as verified(template). A public template scope requires the common
checker to close those obligations under a scope selected before checking,
without fabricated values or a second checker. No template success or unsupported
preparation-write path is introduced by these declaration conditions.

### Passive operation diagnostic formats

`formatSubmission`, `formatCancellation`, `formatReadFailure` and
`formatEffectUncertainty` render only the original SDK-owned observations used
by their corresponding explanation helpers. They offer `text`, `html` and
agent `json` formats, locale selection and a 1,024..1,048,576 UTF-8 byte budget
(default 65,536). Copies and forged errors/responses have no formatting custody.
The renderer captures the retained observation before reading display options.
Locale, wording, severity or edits to an enumerable error never change its facts.

All original lookup references, returned-row counts, unknown outcomes, unresolved
Effect names and physical-stop/control revisions remain intact. JSON carries the
whole explanation and independent operation translation revision; text/HTML
retain those same facts as escaped data. Markup, terminal controls and bidi marks
are escaped without changing parsed JSON values or semantic identities. No raw
cause, input, credential or provider message is included. References are data,
not executable instructions or durable permission.

If the complete observation cannot fit the requested output budget, return
undefined rather than a success-looking prefix or a reduced unresolved-Effect
set. Existing explanation helpers remain available independently. Formatting
performs no lookup, cancel, resend, new read, Compute or provider call. It cannot
establish durable cancellation-operation reconciliation, Delivery opening or
receipt-backed completion, or complete template scope; those still require
facts from their existing authoritative owners. No wire schema, identity,
persistence or execution path changes are introduced by presentation.

## Rejected Run observations

`status`, `wait` and `reconcile` capture the response's enumerable data before
reading its fields or classifying it, then use the existing registered Run state
validator before and after detachment. Each captured field is read once, including
shared nested values; accessors are allowed, but throwing getters are refused.
Request lookup, held submission, Run cancellation and Delivery lookup use this
same capture boundary. Capture does not invoke `toJSON`, normalize numbers or
strings, or change the separate request serialization owner.

A valid observation retains its
original facts even if a Local transport reuses an object. The detached copy must
also preserve all admitted facts, including exact Effect names, physical-stop
facts and control revisions. A different well-shaped value is rejected. Effect
presentation uses that admitted copy without another conversion. A rejected state still
throws `InvalidHostRunState` for a rejected decoded state, or the existing
`InvalidHostResponse` for decoding/wire-bound failure;
`explainRunObservationFailure(error)` distinguishes
an unknown state under the current version (`uninterpretable/unknown_state`),
a usable mismatched version (`protocol_failure/contract_mismatch`), and malformed
known facts or unreadable payload (`protocol_failure/malformed_response`).
The generated `runStateProtocol` vocabulary comes from the registered schema;
it neither admits replies nor changes a Run Owner's transitions.

The original SDK error privately retains only safe typed classification, the
operation name and a read-only `status` candidate bound to the attached Run's
original reference. A rejected response contributes no state, revision, Effect,
publication, physical-stop or cleanup fact. Unknown provider text and raw causes
are omitted from the protocol error. Explanation/locale edits confer no write
retry, cancellation, Compute restart or reconciliation authority. Status lookup
continues to enforce current Host authorization; the retained reference grants
no access. Copies, serialized or forged errors have no explanation custody.
Failure to obtain an observation, including credential, transport or closed-Client
refusal, retains `unavailable/observation_unavailable` separately from received
malformed facts. The error preserves only public Client code/status metadata;
borrowed messages, nested causes and provider details are discarded. Unreadable
error metadata retains only generic `ClientTransportUnknown`, without its cause.
A fresh error owns each call's original target even if the transport reuses an
exception.
The same explanation and formatter accept the original `QueryObservationUnknown`
error from `client.sql` or `client.aql`. That wrapper inherits only the existing
SDK-owned observation explanation. `getSubmissionInput(error)` also retrieves
the immutable submitted input for an admitted short-query failure, including
valid unsuccessful or blocked Run states. Such states retain their validated
observation and have no failed-observation explanation. Copies retain neither
association. Formatting, repeated awaits and query collection after rejection
do not submit, observe or read again.
No dispatch, acceptance, Run outcome or current access is certified by this
classification. No automatic lookup or additional operation is performed by
presentation.

This SDK weak association lasts only while its original error remains reachable;
there is no timed retention guarantee or new Host persistence/retrieval API.
The current Graph contracts and their identities are used without old aliases,
fallbacks or reinterpretation of stored Run identities. This boundary completes
only the rejected Run-observation part of X6; durable write/cancellation/Delivery
contracts and their other diagnostic obligations remain separate.

### Public check Reason catalog

`getCheckReasonCatalogInfo()` identifies the public check catalog revision and
its facts schema separately from translation revisions. `getCheckReasonCatalogEntry(code)`
returns immutable semantic-condition, disclosure, original-location-role and
presentation metadata for a known code; unknown codes return undefined.
Severity and family describe presentation, never the check verdict, action
permission, Run outcome or a retry policy. The existing checker/disclosure
projection emits facts before the generated SDK advice selects a template.

The catalog's closed Reason schema feeds the existing outcome/wire generator,
which also checks generated SDK metadata/types and the [reference catalog](https://github.com/actql/actql/blob/main/docs/reference/check-reasons.md).
Literal scenario expectations remain independent tests. This public catalog is
separate from legacy actql-diagnostics/0.1 and runtime operation outcomes; it
does not claim a legacy compiler catalog body or complete diagnostics coverage.

`explainRequestLookup(lookup)` and `formatRequestLookup(lookup, options)` explain
only the original SDK lookup or its rejected observation. An absent record does
not prove non-acceptance; a returned Run reference does not prove Run success.
Durable held responses retain `preparationState` (`waiting_checkpoint`,
`resuming`, or `ended`), the preparation attempt ID and durability. An ended
preparation is separate from physical stop, cleanup, and execution outcomes.
The helpers ignore open reason/error strings and preserve an original authorized
lookup candidate without granting permission to resubmit or answer a Checkpoint.
Held submit results expose the same preparation facts through `explainSubmission`.

Lookup snapshots are cloned, revalidated and recursively frozen. Invalid copies
and malformed/unknown branches retain an uninterpretable observation and original
lookup target; transport failures retain lookup uncertainty. Copies receive no
explanation custody or submitted-input association. Presentation performs no I/O,
retains the approved English/Japanese localization, and preserves identical facts
in text, HTML and JSON. There is no new Host storage or timed retention guarantee.

Lookup failures use fresh SDK errors for each call. Reused credential or
transport exceptions cannot replace an earlier call's lookup target. Only the
existing SDK error code and a bounded HTTP status are copied; borrowed exception
causes and fields receive no explanation custody or outcome authority.

`explainRequestCancellation(result)` and `formatRequestCancellation(result, options)`
retain the admitted `cancelRequest` branch and original request ID. They keep
recorded cancellation separate from physical stop, Effects and release. With a
Run reference they offer a current `status`; otherwise they offer the original
request lookup under current authorization. Already-terminal does not identify
the terminal Run outcome. The lookup candidate is not a cancellation receipt or
an immutable cancellation-operation identity.

A failed exchange or rejected response retains only an unresolved observation
and the original read-only target. Existing error code/status metadata does not
select an Owner outcome. Successful replies are detached, revalidated, checked
for unchanged identity/branch/revision and recursively frozen. Failure wrappers
are per call; copied responses/errors receive no explanation or input custody.
The existing error recovery fields remain available, but formatters never render
raw causes. Recovery causes retain only public Client code/status metadata,
not borrowed messages, locators, cleanup handles or nested causes. English/default and approved Japanese localization preserve the same
facts, and formatting performs no lookup, retry, execution or release.

A failed `result.deliveryAttempt(attemptId)` lookup keeps safe read-only advice
for that same attempt through `explainDeliveryAttempt(error)` and
`formatDeliveryAttempt(error)`. `lookup_unavailable` means the exchange did not
complete; `lookup_uninterpretable` means no response facts were admitted. Neither
establishes whether the read opened or delivered, permits another opening, or
changes the Run. Explicit lookup still checks current Host authorization.

`formatRunObservationFailure(error, {format: 'text' | 'html' | 'json', locale, maxBytes})`
renders only the original SDK error's retained classification and read-only Run
lookup candidate. Unavailable, unknown-state and malformed/mismatched observations
remain distinct. It performs no status lookup, resend, cancellation or execution.
Copies have no formatting custody. The existing operation display byte budget,
escaping and independent translation revision apply; insufficient budget returns
`undefined` rather than truncated facts. English is the default.


### Explaining independent Owner observations

```js
import {explainOwnerObservations, formatOwnerObservations} from '@actql/sdk';

const views = await run.observeOwners({maxEntries: 10, maxWireBytes: 65536});
const explanation = explainOwnerObservations(views);
console.log(formatOwnerObservations(views, {format: 'text'}));
```

These accessors perform no I/O. Only the original SDK-admitted result has an
explanation association; parsed, copied, foreign and rejected responses do not.
The association retains the original Run reference, connection scope, requested
limits and cursors, disclosed Owner views and revision vector. Transport response
reuse or later observations cannot change an earlier explanation. It lasts only
while the original SDK result is retained and grants no fresh disclosure access.
A new `observeOwners()` call always uses the Host's current authorization.

Views are `non_atomic` and `owner_local`. A Run's control revision is not a
composite observation revision. The current Run view supplies no formal history;
Effect history comes from the existing durable Ledger. A snapshot without its
own revision remains without that revision in the explanation. A snapshot does
not repair a history gap, and history does not replace a failed current snapshot.

The explanation distinguishes history `not_provided`, `retention_expired`,
`history_unrecoverable`, `cursor_mismatch`, `cursor_expired`, `limit_exceeded`,
`acquisition_failed` and a returned `page`. Cursor expiry is separate from
Owner-certified history retention expiry. Protected unavailable views contain
no stream identity or inferred absence. Unmatched cursors retain only the Host's
generic request-position result, without inventing a stream or absence proof.

Reobservation and cursor use are explicit application decisions under current
authorization. A cursor or explanation grants no execution, resend, cancellation,
reconciliation or release permission and does not change the original Run.
Formatters preserve complete admitted facts in text, escaped HTML or agent JSON;
an insufficient output budget returns `undefined` rather than partial facts.
Missing translations use the same safe English wording.

`client.startSource(text, {format: 'aql'})` selects the same query compiler for
SQL/Pipe and admitted Graph forms. It accepts typed `parameterDeclarations`,
keeps the authored format in the submission, and does not autodetect input.
Existing `aql-text` sources and helper defaults keep their original spelling.
