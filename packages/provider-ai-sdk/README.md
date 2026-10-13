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

The original installed read declaration also selects immutable
`currentStateCodec` limits (`quantum`, `comparisonWork`, `decode`) for its
existing Writer/read/comparison child. Those finite serializer limits are not
physical funding. The original installation's missing selection refuses
before a child is created; request data or a copied declaration cannot supply
it. When the existing authorization gate returns dispatch, the original Run
caller saves its quiescent resource state through the same selected Store,
confirms the same journal cut, and consumes that journal's invalidation through
the original Resource Owner before the next Model advance can create an Entry.
Waiting approval does not perform that transition. Save/COMMIT loss keeps the
same failed Promise, park and custody without blind retry. This fence removal
does not issue InferAllow or bypass current authority/egress/Entry/send checks.
The original codec and dispatch-cut record/Promise overlap still require full
installation funding; normal public startup and restore are not established
by these private Store/journal tests.

The private physical preflight can retain the original operation's raw binder
before Approval. Its installed continuation supplies one actual Store persistence
port after nominal raw registration, before returning dispatch and creating an
Entry. Known missing Store/wake installation refuses before Approval. Registration
pending is not a fabricated capture grant: the existing approval path must finish
binding first. The port belongs to that exact operation and registration; copies,
another operation and rebinding refuse. A missing binding observed after an Entry
cannot start transport or regain the consumed attempt when a late binding arrives.
It keeps the original Unknown/cleanup responsibility. This is the initial private
one-Slot connection, not accepted public funding or multi-Slot raw persistence.

The private Chat port validates output and observations from the original saved
raw response, not the SDK-normalized result. After that same SDK settles, it
retires only its unused decoded-result alias, even if raw persistence or cleanup
remains pending. Original raw bytes, request/transport/reader custody, the saved
view, failure/Unknown and explicit same-call reconciliation remain unchanged.
Native callers retain their existing explicit one-time decoded-result transfer;
an already transferred immutable view is never mutated by alias retirement.
This is not physical GC or capacity release. The parsing/normalization peak and
all remaining Promise/Store/closure overlap still require complete funding.

The internal `createInstalledOpenAIChatRegistration` assembles the existing Host
`registerModelProviders` entry from trusted, already retained installation
selections. It does not load packages, derive a numerical profile or reconstruct
opaque Owners from CIDs. Missing originals or a missing consuming runtime hook
refuse before Provider installation. Exact Task/selector/payload selection is a
byte/string comparison; Common retains schema interpretation and validation.
Projection, request and response bounds are distinct immutable declarations.
The selected SDK, endpoint, generation completion basis, original raw profile,
quantity and read selections stay with their existing Host/Model Owners.

This is private assembler preparation, not the public user installation API:
the package still has no public exports. The Host must verify actual builder,
codec, build/lock and validator originals and supply justified complete physical
funding before public use. Frozen objects, matching declarations and fixture
allowances do not establish those facts. The public entry and external-package
example remain dependent on that original installation/funding acceptance.

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

The private native `prepareTypeSafeDecisionRequest` reuses that same interceptor
and fixed transport with the selected TypeSafe v4 `doDecide` operation. It sends
all mapped questions against one state without generation settings, high-level
retries, default-provider mutation or SDK workflow restoration. Its input must
come from the original bounded Common Decision projection and funded caller;
the private builder itself does not admit a Task or validate native answers.
The private `prepareProjectedTypeSafeDecisionRequest` consumes the opaque
Common projection view and rechecks its original Provider/request membership,
Task/prompt/output-schema CIDs and authored selector before SDK allocation.
It passes Common's positional question/option aliases unchanged to the pinned
native SDK and checks the actual intercepted request against the immutable
projection wires. Only the SDK's Boolean-to-`noul` representation is mapped;
no generation defaults, question evaluator or answer validator is added.
The caller retains the separate original view until Common's answer mapping
retires it. Parsed input trees, verification trees/callback and SDK overlap
require the original full funding before use, not a grant from codec clamps.
Selected Node tests use actual SDK execution with Common boundary doubles and
synthetic responses. They are not actual Common-to-SDK or public Run acceptance.

Common native raw decode/completeness, registered physical
profile/precision, original Store receipt and installed caller remain unconnected.
SDK model fallbacks and reported rounding are not provider observations or
profile authority. Prototype-key SDK response refusal keeps original raw bytes
and no repair call; it does not prohibit legal Common IDs. This preparation adds
no public/native capability or numerical profile. The generation SDK closure and
the native SDK's separately pinned dependency closure remain distinguishable.

Formal packaging, external consumer, public Local/HTTPS, real model acceptance,
four parallel calls, Decision and Cloud are unfinished M0–M5 work.

### Private native Decision request projection

The Common `start_native_decision_projection` child projects an original
admitted Decision request without dispatching it. The Node consumer exposes
the same opaque cursor and escaped request view; neither is an installation,
capacity, approval, response-completion or send grant. This preparation is not
part of the initial Node generation gate.

Questions remain borrowed from the original admitted prompt. Fixed-width
position aliases preserve ordered question/option correspondence without
banning legal IDs such as `__proto__`. The escaped view retains the original
IDs and exact Task/prompt/schema/selector binding for a later response codec.
Retiring the emitting child does not retire an escaped view. The original
parent must fund and retire both lifetimes, including retained empty backing
arrays, writers and request strings. No physical numeric profile is supplied.

The initial physical subset accepts text and JSON-compatible state, preserving
empty text, null, numbers, booleans, arrays and Unicode/newlines. The typed JSON
carrier is unwrapped before its original value is emitted by Common; JS must
not reconstruct the value. Unsupported typed state and the selected SDK's
question-count limits are physical refusals, not common language restrictions.
Native answer decoding, original raw Store binding and public Decision
execution remain unconnected; do not route this view through the generation
`SavedChat` completion codec.

The private answer projection now consumes an already admitted original raw
response tree and the same Common request view. Common maps positional question
and option aliases back to the original IDs, emits distributions in original
order, and preserves the actual Choice/tie, fractional Score and Boolean
probability. Missing, extra or mismatched aliases refuse; no value is rounded
or normalized. The existing Decision validator and output admission remain
mandatory and independent of this DATA mapping. Unknown response metadata
stays in the original raw custody rather than being copied into the answer.

This finite synchronous codec has explicit output/work limits; it is not a
cooperatively preemptible response cursor or an endpoint-completion assertion.
Its admitted tree, lookup maps, output writer and escaped wire overlap must be
funded before installation. The Node wrapper delegates to Common without
implementing a second answer mapper. No native installed capability, saved raw
receipt, physical numerical profile or public execution is enabled by it.
