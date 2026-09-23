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
The Client serializes the submitted Program and parameters before awaiting an
asynchronous credential callback, so later mutation of caller objects cannot
change that transmission. An application that may need to resend must retain
its own original input and explicit request ID.

`attach(ref)` retrieves another handle for the same Run. `result(name)` only
selects a named Result. Each `rows()`, `batches()` or `all()` call creates a
new delivery attempt; a reader exposes `attemptId` before iteration.
`deliveryAttempt(id)` inspects the existing Host attempt and release receipt
without sending payload. A release receipt never proves that the Client
received or saved every value. A reader reaches `complete` only after the
normal wire terminator; values yielded before a failure are a prefix.

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
