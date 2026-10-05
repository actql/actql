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

A completed check may be invalid or undetermined. Its verdict is always bound to
scope/context and does not start or authorize a Run. Wrong supplied types expose
expected/actual types without values. Missing declared values expose Requirements
and remain undetermined in bound-input scope. Unsupported checking and budget
exhaustion are not author errors. Inaccessible and absent installed Source aliases
share unresolved coverage; an independent public violation remains visible.

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
An editor must associate its open-document session/version with the submitted
snapshot and pass the current identity/revision/text when displaying against
the current buffer. Reopening or editing does not rebind an old response.
This helper provides UTF-16 coordinates, not a negotiated LSP server or an edit
operation; approximate ranges retain their label and do not grant edit permission.
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

### Graph components argument explanations

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

This coordinated extension changes the registered `actql-check-reason/0.1`
body and dependent outcome schema identities, validators and SDK wire types.
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
