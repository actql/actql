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

The Client also caps each JSON control response at 1 MiB of wire bytes,
including connection, submission, status, lookup and Host error bodies. It
cancels an oversized delivery without treating a submit ACK as a known
failure: `SubmissionUnknown` still carries the original request ID. This is
a Client transport bound, separate from Result read limits and from the
Host's Run resource accounting.

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
