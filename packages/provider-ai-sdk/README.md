# AI SDK private physical preparation and transport

This private, unfinished optional package has no public exports or installed
capability. It is not a published provider or permission to send model requests.

The first physical preparation uses the pinned OpenAI SDK's v4 chat generation
operation. It starts the SDK exactly once and intercepts the final request
without networking. An opaque handle retains the original SDK invocation until
its response is supplied or cancellation settles. Raw SDK exceptions are not
exposed as diagnostics. No synchronous Model executor is added.

The private original-request consumer obtains generation settings from the
admitted MoonBit Task rather than inventing SDK defaults. It preserves requested
temperature, top-p, output-token limit and optional seed. Decision has no such
settings and refuses this generation builder. Integers outside the selected
SDK's exact Number range refuse before preparation; this is not a restriction
of the common Task's Int64 domain. The pinned JS ABI's signed Int64 interpretation
is explicit. The installation still owns model-selector mapping, admitted
prompt/schema, credentials and physical-profile compatibility; this projection
does not establish any of them. The actual fixture verifies this mapping only
for its selected non-reasoning chat profile, not every OpenAI model.

The additional private admitted-request consumer reads the closed
`actql.openai_chat_prompt/0.1` payload, mapped input wire and strict output
schema from Common's original admitted Provider/Task. It binds the Task,
prompt and output-schema CIDs plus the selector before SDK preparation. Empty
instructions are explicit and valid; missing, NULL or extra payload fields
refuse. One separate data-text message keeps Common's exact input wire,
including Decimal strings, without parsing it back into JavaScript values.
The actual intercepted SDK request must match those originals and authored
generation settings. An SDK model-dependent rewrite refuses, with no fallback.

The bounded schema emitter supports a nonnullable closed Object root, plain
Text/Number/Boolean/Array/Object children and explicit nested nullability.
All fields are required. Unsupported constraints and other value kinds refuse
before send rather than being weakened. This is not a language-wide ban or
Common output validation. The convenience private request consumer uses finite
preparation work/byte/node/depth/frame limits; it is not evidence of cooperative
SDK JSON parsing or a funded public physical-preflight installation.

The additional private `createAdmittedOpenAIChatPreflight` consumes one Common
projection-child transition per physical-preflight advance. It allocates that
child only after the existing port validates its installation; projection
completion retires its borrows before starting one SDK preparation. Cancellation,
refusal and retirement failure preserve the original cleanup path without a new
request. The resulting plan still uses the existing fixed transport/Entry/send
gate and raw-save port. SDK initialization and JSON work remain external
synchronous work, not a new cooperative guarantee. The child's nine fields,
phase payloads, output tuple and Node progress reference/callback/context overlap
must be funded before normal startup; this private integration supplies no
numerical layout, public capability or execution permission.

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
