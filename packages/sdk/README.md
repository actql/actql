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
to inspect the existing request without starting Compute. An unknown response
does not prove nonacceptance, and the SDK does not retry automatically.
Profile, admission and request-lookup replies use the public
`@actql/client-wire` validators, including exact connection and durability
bindings. A found request lookup must echo the requested ID. A malformed or
foreign acceptance does not become a known Run.
The Client serializes the submitted Program and parameters before awaiting an
asynchronous credential callback, so later mutation of caller objects cannot
change that transmission. `getSubmissionInput(result)` retrieves this call's
detached, deeply frozen JSON request input from its returned Execution,
`SubmissionUnknown` error or `RequestHeld` error. It includes the original
request ID, submission kind, Program or text with declarations, supplied
parameters, connection selection and lookup context. Local and HTTPS use the
same JSON-value snapshot. Text is not normalized or converted to different
newlines. Credentials and signing keys are not added to this snapshot.

```js
import {getSubmissionInput} from '@actql/sdk';

try {
  const execution = await client.start(program, {requestId, parameters});
  const submitted = getSubmissionInput(execution);
  // Compare the accepted handle with this call's original input.
} catch (error) {
  if (error.code !== 'SubmissionUnknown') throw error;
  const submitted = getSubmissionInput(error);
  // Inspect the original request; do not submit the edited Program again.
  const lookup = await client.lookupRequest(submitted.requestId);
}
```

`explainSubmission(result)` returns a deeply frozen explanation for that exact
SDK result. The validated submit branch fixes its observation independently of
error `code`, message, severity or HTTP status: `acceptance_unknown` for a lost,
malformed or foreign reply; `run_reference_received` for a validated Run
reference; and `request_held` for a validated held response. The first says that
work may already have started and names the original `lookupRequest` target and
connection scope. A returned Run reference instead names its read-only `status`
inspection. A held response names request lookup and does not promise a current
preparation or execution state. These are presentation facts from this call,
not a new server acceptance contract or an execution/publication/release proof.

```js
import {explainSubmission} from '@actql/sdk';

const explanation = explainSubmission(result);
if (explanation?.next.operation === 'lookupRequest') {
  // Use the original Client and its current authorization for this lookup.
  const observation = await client.lookupRequest(explanation.next.requestId);
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

```js
import {explainEffectUncertainty} from '@actql/sdk';

const state = await execution.status();
const explanation = explainEffectUncertainty(state);
// Display the unresolved Effects and physical stop separately. Any explicit
// follow-up status request must use the original Client and current authority.
```

The helper performs no transport or write, and its only advice is to observe
the original Run's current status. It does not promise that the Host offers
reconciliation, authorize resubmission, infer rollback or assert resource
release. The immutable explanation preserves what this response reported;
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
`open_unknown`, the original `attemptId`, and zero returned rows. Inspect
that attempt with `deliveryAttempt(id)` before deciding on an explicit new
read. A `not_found` lookup does not prove that opening never committed, and
lookup never reopens the payload or consumes another grant use.
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
import {getCheckInput, resolveCheckLocation, explainCheckReason, explainCheckOutcome} from '@actql/sdk';

const outcome = await client.check('SELECT @missing AS n', {format: 'sql'});
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
  format: 'sql', parameterDeclarations: {x: {type: 'number'}}, parameters: {},
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

The SDK detaches each validated check response before binding input snapshots
and freezing the received observation. A Local Host can reuse its response
objects; later replies cannot replace an earlier outcome, context, input or
location association. Completed and failed partial reports keep their own
submitted inputs. Unavailable responses provide no bound report or snapshot.
Uncloneable replies or replies whose copied shape violates the wire contract
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
Unaliased-column failures lacking a typed expression diagnostic remain generic.
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
const observation = await document.check({format: 'sql'});
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
response or uncertain error produced by this SDK's `Execution.cancel()` call.
The SDK detaches each validated cancellation response, so a Local port reusing
its response object cannot change an earlier result's Run, kind, revision or
explanation.
The detached value is revalidated against the response schema and all three
original Run fields. Clone failures or changed fields raise
`InvalidHostCancellation` with the original Run's `outcome_unknown` advice;
they never trigger another cancellation request.
Validated `accepted`, `already_requested` and `already_terminal` observations
retain the Host's control revision. The summary distinguishes recording a
cancellation request, an existing request and a Run already terminal for
cancellation. Each provides a `status` target for the same retained Run
reference. Cancellation acceptance establishes no physical-stop, external
Effect outcome or resource-release fact.

Transport loss, malformed replies and differently bound replies retain an
`outcome_unknown` explanation without a fabricated recorded revision. An HTTP
`Response` object returned through Local is also an invalid representation with
an unknown cancellation outcome; its existing SDK error is preserved. Changing
an error code/message or a returned response after the call does not change
its bound explanation. Handwritten, parsed or copied objects have no SDK
association. Local failures before the send boundary and typed Host refusals
retain their existing errors without a fabricated cancellation observation.
The accessor performs no I/O or automatic retry and retains no provider cause.
The association lasts only while its SDK result is retained; no timeout or
persistent Host custody is added.

This is presentation over the existing Client–Host cancellation contract.
No wire/schema/CID, cancellation ledger or execution semantics is replaced.
The current public Run cancellation response has no cancellation-operation
identity or exact-operation lookup. A Run status refresh cannot reconcile a
particular lost cancellation; it only observes current Run state under current
authorization. The existing control owner must provide that operation's
identity, immutable intent, revision conflicts and reconciliation contract
before the complete cancellation-outcome design can be exposed. A recorded
physical-start/close control fixture does not prove delayed live-worker stop
or external Effect reconciliation.


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
const outcome = await client.check(text, {format: 'sql'});
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
const observation = await session.check({format: 'sql'});
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

`status`, `wait` and `reconcile` use the existing registered Run state validator
before and after detaching the received value. A valid observation retains its
original facts even if a Local transport reuses an object. A rejected state still
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
Credential and transport refusals retain their existing separate behavior and
are not labelled as received malformed state observations. No automatic lookup
or additional operation is performed by presentation.

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
which also checks generated SDK metadata/types and the [reference catalog](../../docs/reference/check-reasons.md).
Literal scenario expectations remain independent tests. This public catalog is
separate from legacy actql-diagnostics/0.1 and runtime operation outcomes; it
does not claim a legacy compiler catalog body or complete diagnostics coverage.
