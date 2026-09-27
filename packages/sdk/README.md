# `@actql/sdk` development artifact

This lightweight package implements the public Client, Execution and Result
transport API for an already installed Client Host. It contains no Local
kernel, native binding, DuckDB adapter or Cloud policy. The current OSS Host
HTTP bridge supports real published-Result reads and status for committed
successful Runs. Generic Program submit, durable request deduplication, and
full active-Run status are not yet installed, so this artifact is not a
complete standard distribution.

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
its own original input and explicit request ID.

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
transferred through that ABI; the Client enforces wire and decoded-value
bounds independently. The provider must enforce its own pre-transfer row
bound, current authorization, and Run ownership before yielding a frame.
The port's `AbortSignal` belongs only to that observation or read attempt.
This boundary does not install a provider or imply that the current
`@actql/node` artifact supports embedded Local.

`attach(ref)` retrieves another handle for the same Run. `result(name)` only
selects a named Result. Each `rows()`, `batches()` or `all()` call creates a
new delivery attempt; a reader exposes `attemptId` before iteration.
`deliveryAttempt(id)` inspects the existing Host attempt and release receipt
without sending payload. It rejects a reply bound to another attempt, Run,
Result or serialization contract, and invalid record/receipt combinations.
A release receipt never proves that the Client
received or saved every value. A reader reaches `complete` only after the
normal wire terminator; values yielded before a failure are a prefix.
An empty JSONL record fails the attempt instead of silently omitting a row.

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
