# `@actql/sdk` development artifact

This lightweight package implements the public Client, Execution and Result
transport API for an already installed Client Host. It contains no Local
kernel, native binding, DuckDB adapter or Cloud policy. The installed Node Host supports Program submission within its
installed profile, durable request lookup and deduplication, active and terminal
Run observations, and published Result reads. Supported Program shapes and
connectors depend on the installation; this is not a claim that every Host
supports every Program. See the [current implementation status](../../docs/reviews/current-product-status.md).

`connect(options)` authenticates with the selected Host and returns its
confirmed owner, durability and capability snapshot. `aql(text,
{format: "json" | "yaml"})` and `start(program)` send one admission request
immediately and resolve only after an acceptance response. Both accept
`requestId`. An omitted ID is generated before send; an uncertain submission
error exposes that ID and a lookup context. Call `lookupRequest(requestId)`
to inspect the existing request without starting Compute. To resubmit after
an ambiguous response, use the original entrance with the same ID and exactly
the same intent; safety depends on the Host's atomic deduplication and its
documented request-record retention horizon.
Profile, admission and request-lookup replies use the public
`@actql/client-wire` validators, including exact connection and durability
bindings. A found request lookup must echo the requested ID. A malformed or
foreign acceptance does not become a known Run.
The Client serializes the submitted Program and parameters before awaiting an
asynchronous credential callback, so later mutation of caller objects cannot
change that transmission. An application that may need to resend must retain
its own original input and explicit request ID. After an unknown response,
retain the original connection selection as well: `lookupContext` identifies
the endpoint and Host-reported scope for investigation, but does not grant
access or authorize looking up the request through a different Workspace or
embedded Host root. Reconnect never submits automatically.

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
A release receipt never proves that the Client
received or saved every value. A reader reaches `complete` only after the
normal wire terminator; values yielded before a failure are a prefix.
Installed Local delivery also propagates its owner's terminal-record or
receipt failure after a normal terminator, retaining the failed attempt.
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
[Result description semantics](../../docs/design/result-description.md).

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

`execution.cancel()` retains the existing `execution.ref` and sends one Run
cancellation request. A transport error or Host failure does not establish
whether cancellation was recorded; the SDK does not automatically resend it
or start another Run. Keep the original Host connection and Run reference.
After access is restored, `status()` on that handle, or `attach(ref)` followed
by `status()`, can observe the same Run. A Host that supplies `control` reports
its retained `revision`, `cancellation_requested` and `physical_stop`; absence
of `control` supplies no cancellation observation. Accepted cancellation alone
never proves physical stop. Current authorization applies to these operations.

This existing Run observation is not a lookup of a distinct cancellation
operation. `Execution.cancel()` currently has no cancellation-operation ID,
operation-scoped lookup or dedicated unknown-outcome error carrying recovery
context. In particular, a later `cancellation_requested: true` does not identify
which caller's cancellation was recorded. Do not infer automatic retry or
operation-specific reconciliation from it. The separate `cancelRequest` and
Checkpoint recovery contracts below remain unchanged. See the
[bounded write-response-loss inventory](../../docs/reviews/2026-10-02-sdk-write-response-loss.md).

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

## Held requests and Checkpoints

A Host may hold a request before any Run exists. For example, its account
configuration can delegate Run acceptance on a protected Site, and the Host
defers the decision to a durable Checkpoint. `aql()` and `start()` then
reject with `RequestHeld`. That is a control result, not a failure and not an
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
import {connect, RequestHeld} from '@actql/node';

const endpoint = 'https://remote-host.example/';
const owner = await connect({mode: 'remote', endpoint, token: ownerToken});
let execution;
try {
  execution = await owner.aql(documentText, {format: 'json',
    requestId: 'nightly-1'});
} catch (error) {
  if (!(error instanceof RequestHeld)) throw error;
}

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

```js
import {getCheckInput, resolveCheckLocation, explainCheckReason} from '@actql/sdk';

const outcome = await client.check('SELECT @missing AS n', {format: 'sql'});
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

A completed check may be invalid or undetermined. Its verdict is always bound to
scope/context and does not start or authorize a Run. Wrong supplied types expose
expected/actual types without values. Missing declared values expose Requirements
and remain undetermined in bound-input scope. Unsupported checking and budget
exhaustion are not author errors. Inaccessible and absent installed Source aliases
share unresolved coverage; an independent public violation remains visible.

Locations use the immutable original input snapshot, not the latest editor buffer.
`resolveCheckLocation` returns `undefined` for a copied report, missing snapshot,
stale revision, changed content or invalid byte boundary. Supplying its optional
current-input argument validates the same identity/revision/content. Text spans
are UTF-8 byte intervals; structured values/declarations have revision-bound
pointers. There is no SDK parser, automatic fix or Host input re-fetch API.
Nested object/array type failures identify the declared child type and the
existing binder's path, with JSON pointer escaping for field names. Supplied
constraint violations can carry that path with their safe generic reason.
Missing submitted nodes and pointers beyond the public bound have no location;
invalid defaults never point into supplied values. Values remain in the local
submitted snapshot, not in public diagnostic facts.

This coordinated correction changes the closed `actql-check-outcome/0.1` schema
and introduces `actql-check-reason/0.1`. Schema identity, validator and SDK/Host
must match; a mismatched reply throws `InvalidHostCheckOutcome` and never becomes
success or an empty diagnostic report. Existing `actql-diagnostics/0.1` is a
separate contract. Original snapshots remain weakly associated with the response;
retaining a response or a retrieved snapshot retains its submitted input.
