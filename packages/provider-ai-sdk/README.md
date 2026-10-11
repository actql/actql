# AI SDK provider preparation

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
send gate still need to be connected. This preparation alone sends nothing,
does not issue completion/capture evidence and does not authorize transmission.

The SDK's decoded result is not Common output validation or provider-reported
metadata. Preserve the separately bounded raw response, endpoint completeness,
nullable observations and original capture through the existing Owners. SDK
result objects, request copies, parser work, pending Promises and cancellation
all remain part of C's full funding before public adoption.

The package lock freezes the actual dependency closure. Preparation tests use
the real pinned SDK with synthetic supplied responses and no live network.
Formal packaging, external consumer, public Local/HTTPS, real model acceptance,
four parallel calls, Decision and Cloud are unfinished M0–M5 work.
