# AI SDK private physical preparation and transport

This private, unfinished optional package has no public exports or installed
capability. It is not a published provider or permission to send model requests.

The first physical preparation uses the pinned OpenAI SDK's v4 chat generation
operation. It starts the SDK exactly once and intercepts the final request
without networking. An opaque handle retains the original SDK invocation until
its response is supplied or cancellation settles. Raw SDK exceptions are not
exposed as diagnostics. No synchronous Model executor is added.

The existing Common Model Owner must admit the Task, original inputs, complete
Slot inventory, profile and all simultaneous holdings before using this code.
The existing original Entry, durable journal acknowledgement and one-shot final
send gate still need to be connected. Preparation alone sends nothing. The
private transport accepts only an explicitly installed fetch primitive and the
original intercepted request; it cannot issue completion/capture evidence or
authorize transmission.

Before consuming Common's send gate, the installed caller prepares the fixed
transport and bounded response limits with `prepareSdkTransport`. After that
gate, `startSdkTransport` invokes that same request immediately, without an
intervening notification, await, request reconstruction or retry. A synchronous
throw or lost response remains unknown responsibility, never proof of non-send.
These private functions are not public capability or admission APIs.

The response reader bounds bytes, individual chunks, chunk count and selected
headers before feeding a separately funded Response copy to the original SDK.
It preserves raw bytes and incomplete prefixes. HTTP EOF is not endpoint or
answer completion. A cancel-induced stream EOF is explicitly incomplete.
No unbounded `text`, `json`, clone or tee precedes the byte check. The pinned
SDK's subsequent synchronous JSON/schema work is not proven cooperative by
this reader; Common's bounded codec and validation remain necessary.

Cleanup retains the same pending transport, unread body or failed reader
retirement and retries that responsibility, not the request. Local abort or
physical reader retirement does not prove remote stop, Run cancellation,
capture persistence or reservation release. The original Common Owner must
retain unknown/evidence custody independently. Escaped raw views and transferred
decoded values remain the receiving Owner's responsibility.

The SDK's decoded result is not Common output validation or provider-reported
metadata. Preserve the separately bounded raw response, endpoint completeness,
nullable observations and original capture through the existing Owners. SDK
result objects, request copies, parser work, pending Promises and cancellation
all remain part of C's full funding before public adoption.

The package lock freezes the actual dependency closure. Preparation and
transport tests use the real pinned SDK with synthetic responses and explicitly
installed fixture fetches, with no ambient or live network.
Formal packaging, external consumer, public Local/HTTPS, real model acceptance,
four parallel calls, Decision and Cloud are unfinished M0–M5 work.
