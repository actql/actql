# Optional AI SDK Host installer (development)

This private development package provides configured and lower-level
registration callbacks for the installed Node Host.
Registry publication and live OpenAI acceptance remain separate work.

For development-package acceptance, install the optional provider tar alongside
the five matching normal Client/Host tars. The provider is not bundled into
`@actql/node`; the five normal tars alone do not supply this import. Use the
original same-source producer artifacts and normal npm lifecycle installation:

```sh
npm install ./actql-client-wire-0.0.0-development.tgz \
  ./actql-sdk-0.0.0-development.tgz \
  ./actql-run-host-core-0.0.0-development.tgz \
  ./actql-local-node-0.0.0-development.tgz \
  ./actql-node-0.0.0-development.tgz \
  ./actql-provider-ai-sdk-0.0.0-development.tgz
```

This is a local tar installation, not a registry release. Do not substitute a
checkout import, private runtime path, or a differently built Host artifact.

## Use a verified SDK registration

Pass the selected `modelSdkRegistrations` to the installed Node Host and use
`createRegisteredSdkProvider` for its `registerModelProviders` callback. Supply
the matching Provider ID, the original request-data-handling contract wire,
generation defaults, bounds, a whole-call timeout and the current egress
observer. The trusted registration supplies the SDK and adapter identities,
and a frozen list of `routes` for one `providerId`. Each route specifies its
alias, resolved model, API mode, endpoint, options and credential reference.
Set `defaultSelector` to one of those aliases. For each route, set
`structuredCapability` with operation `structured_generate` and explicit
`adapter` and `model` statuses. The statuses are `supported`, `experimental`,
`unsupported`, and `unavailable`. The current runtime admits structured
generation only when both statuses are `supported`. The Host reads the
credential only at authorized dispatch.

On the first SDK-enabled Host initialization in a process, include every SDK
and adapter module that later Hosts in that process will need. That first
initialization seals the module inventory. Later Hosts can reuse those same
modules. Selecting an unheld module fails before Provider registration.
Each Host authorizes its own Provider registrations and credential use.

To configure more than one registered Provider for a Host, pass a frozen list
of distinct Provider options to `createRegisteredSdkProviders`. Include every
corresponding registration in the first Host's `modelSdkRegistrations`. A Task
can select its Provider ID and model alias with `model.provider` and `model.name`
in the Task declaration. Each Provider uses its own admitted configuration,
response profile and credential reference.

The pinned Anthropic Messages adapter selects `claude-sonnet-4-6` with
`structuredOutputMode: 'outputFormat'`. Its serial text profile sends
temperature, requires neutral `topP: 1`, and refuses a seed. Put only the
credential reference `ANTHROPIC_API_KEY` in the deployment configuration.

The pinned Google GenerateContent adapter selects `gemini-2.5-flash` with
`structuredOutputs: true`. Its serial text profile sends temperature and
`topP`, refuses a seed, and uses the deployment credential reference
`GOOGLE_GENERATIVE_AI_API_KEY`.

For Mistral, select `@ai-sdk/mistral` `4.0.89` and its `createMistral` export
in the trusted Host registration, with the bundled `_internal/mistral-chat.mjs`
adapter. Set the resolved model to `mistral-small-2603`, the API mode to
`chat_completions` and `providerOptions` to
`{strictJsonSchema: true}`. The Host uses the credential reference
`MISTRAL_API_KEY` as a bearer credential for
`https://api.mistral.ai/v1/chat/completions`. The accepted profile is
serial text with a strict JSON Schema response and no reasoning override.
Controlled HTTPS tests on installed Node 22 and 24 exercised one request,
typed output and a cold Saved read with zero sends. Live Mistral
qualification is pending for this profile.

For OpenAI Responses, select `@ai-sdk/openai` `4.0.91` and its
`createOpenAI` export with the bundled `_internal/openai-responses.mjs`
adapter. Register `gpt-4.1-mini` with API mode `responses`, endpoint
`https://api.openai.com/v1/responses`, and flat `providerOptions`
`{store: false, strictJsonSchema: true}`. The Host uses the
`OPENAI_API_KEY` credential reference. This profile accepts a single
structured text response with a strict JSON Schema.

The Host can provide a frozen `modelGeneration` array to
`createRegisteredSdkProvider` for specific route selectors. Each entry
sets `temperature`, `topP`, `maxOutputTokens`, and an independent
`taskMaxOutputTokens` ceiling. A Task may author `limits.max_output_tokens`
within that ceiling. The selected route's defaults apply when the Task omits
the limit. Provider options, temperature, top-p, seed, and credentials
come from the Host. The provider's existing token budget still applies.

## Configure a Host from project Tasks

`createRegisteredSdkProvider` returns one asynchronous `registerModelProviders`
callback for one Host. The Host loads the project's actual model Tasks and
provider defaults through Common and constructs each Task's profile and execution
originals under the initial Resource. The credential is acquired at authorized
dispatch. Applications supply no runtime,
Task CID, Program CID, physical fetch, response-profile JSON or Resource token.

```js
import {connect} from '@actql/node';
import {createRegisteredSdkProvider} from '@actql/provider-ai-sdk';

const registerModelProviders = createRegisteredSdkProvider({
  providerId: 'models/openai', // Matches the project's model_tasks provider.
  dataHandlingContractWire,
  generation: {temperature: 0, topP: 1, maxOutputTokens: 100},
  transportTimeouts: {connectMs: 300, headersMs: 700, bodyMs: 700, callMs: 1000},
  budget: {
    maxCalls: 2n, maxRows: 2, maxTokens: 1000n,
    maxCostUnits: 100000n, maxDurationMs: 1000n,
  },
  observeEgress: () => currentInstalledEgressFacts(),
});
const client = await connect({mode: 'local', installation: {
  directory: './.actql', modelSdkRegistrations, registerModelProviders,
  authorization: configuredAuthorization,
}});
try {
  // Submit the original Program through the ordinary Client API.
} finally {
  await client.close();
}
```

The account, signer and current egress facts come from trusted Host
configuration. The callback does not authorize its own calls. Egress facts have
`classification`, `region`, `providerRetention` and `trainingUse` fields; Common
checks the actual input policy against them at the original boundary. This
finite text profile accepts public input and forbids training. It selects the
existing serial, non-streaming SDK/Undici transport with no implicit retry,
redirect, tools, media or workflow restoration. Unknown usage remains Unknown.
Explicit positive cost/duration ceilings do not establish observed usage or
invent a provider price.

Different Tasks on the same Provider retain their own exact prompt, output
schema, response profile and read recipe. Selection uses the actual Core
execution Task and checks the same installed base and view after callbacks.
Missing or foreign Task views refuse. Logical occurrences remain independently
charged; metadata sharing does not transfer authority or capacity. Each Run
still requires the original Request/Plan/Scope admission. A missing or too-small
Resource refuses rather than increasing the top-level budget.

The expected SDK-v4 request envelope comes from the same Common writer as the
initial direct HTTP profile. The named SDK profile preserves its omission of
`n` and `stream`; the direct HTTP profile keeps its explicit fields. Node invokes
the SDK and compares the complete resulting JSON with that original wire. It
does not reconstruct generation, message or schema rules in JavaScript.

Before Plan construction, the normal factory adds Common's checked demand for
all prepared rows' expected wires and the serial writer/verification workspace
to the same original Read and Model inputs. Workspace does not become retained
output. The existing actual-body parse, full comparison and SDK base stay
funded without refund. The original budget remains unchanged; these construction
quotes are not an engine/GC heap measurement. Explicit low-level recipes must
also fund this construction under their original Owner.

Create a fresh callback for a new Host, including a later process reading the
same Saved Result. The existing Saved reader consumes its original persisted
result before any new execution; restoring configuration must not resend a
provider request. Keep the same configured endpoint, model, Task files and
software originals. Credential bytes are never Program input and must not be
printed in logs or committed.

## Explicit physical timeouts (development)

The registered factory requires `transportTimeouts` with positive finite
`connectMs`, `headersMs`, `bodyMs`, and `callMs` in milliseconds (integers up to
2,147,483,647). It freezes the values
under the initial construction Resource, includes them in the same original
configuration/contract bodies through Common's canonical constructor, and
passes that selection to the fixed physical transport. Each value must fit
the declared `budget.maxDurationMs`; that validation does not turn a quantity
reservation into an observed duration or a timer.

The existing Undici connector applies `connectMs` through TCP/TLS setup;
`headersMs` waits for complete HTTP headers and `bodyMs` bounds the idle time
between body data. These three phase settings alone are **not** an absolute
whole-Call or total-body deadline. The `callMs` clock starts immediately after
the actual original physical request begins and stops the same SDK controller
if bounded response reading has not settled, including continuous body data.
It does not time Core decoding, Store publication, Result, or Saved restoration.
The whole-Call clock adds Common's logical control quote to the
same per-Task physical profile/Read/Model demand before the original Plan/Scope
admission, without increasing the top-level budget. This is not a full engine,
shared timer-heap, async-hooks or native allocation adequacy certificate.
Timer granularity and event-loop scheduling can delay observation. The original public
low-level registration contract does not accept an unbound timeout override;
the new normal configuration continuation carries the same admitted inputs.

A physical timeout is distinct from a caller's wait timeout and Run cancellation.
It proves neither provider nonacceptance nor remote stop. Entered Unknown and
partial raw originals keep their original attempt, Store and cleanup duties;
there is no automatic retry, fresh Run or fabricated EOF/Result. Connection,
IO and SDK/raw retirement remain separate observations. This does not establish
normal-installed or live acceptance, or close the separate whole-Call deadline
boundary.

The configured Chat installation binds its resolved model ID, adapter and API
mode in the original configuration. Changing the model behind a selector changes
the binding. Pending selector-only originals from before this binding lack
proof of the wire model. A current installation refuses dispatch from them,
including when the selector now equals the configured model ID. Existing
terminal Saved results remain readable through their original Result path.

## Optional usage-only disclosure (development)

`installation.inferEvidence.kind: 'usage'` is a **new explicit opt-in** to a
usage-aware Sink contract. The parent implementation accepted omitted kind or
`'typed-input'`; adding `'usage'` does not change either existing path. This is
local callback DATA for the matching development cohort, not a new artifact
format version, Model evidence protocol, authority or self-CID.

After the original capture is Store-confirmed and its existing publication
Resource admits the copy, `sink.capture` receives the original binding and
`wires: {usage: string}`. That canonical string has exactly these seven keys:
`input_tokens`, `invocation_evidence_cid`, `model_call_slot_cid`,
`model_task_contract_cid`, `observation_origin`, `output_tokens`, and
`raw_response_artifact_cid`. Token and raw-artifact absence is `null`, distinct
from known zero; origin is `reported` or `historical_admitted`. No prompt,
context, rendered input, structured answer or provider metadata is included.

Use a Sink that explicitly understands this new shape. The existing five-part
full-evidence Sink is incompatible and must report incomplete/unsupported;
the Host never fabricates its missing parts or turns that failure into success.
The usage string is **not** a full `model-invocation-evidence/0.1` or `/0.2`
record. Omitted kind retains the full-evidence contract; `'typed-input'` retains
its own input-only contract.

A usage-aware `capture` callback returns an own enumerable DATA
`status: 'complete'` only after its selected copy work settles. The Host selects
that field without enumerating or retaining other callback payloads. Missing,
accessor, proxy or unsuccessful status remains incomplete. `sink.record`
receives the corresponding usage availability manifest. This optional outcome
cannot replace the Model's success/Unknown state, authorize a call or cause a
retry. Current/identity checks, destination authorization, byte ceilings and
copy-child cleanup still apply across both callback awaits. These Source and
component contracts do not establish installed-package or live acceptance.

## Registered SDK request and response ownership

The selected Host supplies the original Runtime, Task and provider binding.
It derives the Read recipe from the admitted profile and binds the Program
definition, parameters and barrier to each actual checked Graph. Complete
funding, the current authority checks and the original approval still belong
to that Run.

The pinned SDK first renders the bounded request without networking. Common
projects the exact Task, prompt, mapped input and strict output schema.
The selected adapter verifies the rendered request against those originals and
the installed route before the original Call can create an Entry.
The original Call holds the same prepared transport, Reader and credential
selection through the final send gate. Refusal or an ambiguous send keeps the
original responsibility and attempt identity.

The original response is bounded and retained as Raw before the selected SDK
receives a response to decode. Common checks the typed answer and binds any
reported model, request, finish and usage observations to that same original
response. Incomplete transport keeps the original entered attempt unknown.
Raw, Store confirmation, cleanup and separate Saved reads keep their own
current checks. Saved does no Provider work.

The SDK dependency lock and shrinkwrap describe the exact same dependency
closure. A different dependency or peer resolution needs a new admitted
selection. The Host loads packages at startup through its verified registry.

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
Installed original raw Store binding and public Decision execution remain
unaccepted; do not route this view through the generation
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

### Private native raw response continuation

The native SDK preflight transfers a nominal saved raw view through Common's
native-only physical poll variant, not generation's `SavedChat`. Common binds
the four original borrows (saved raw, original request, admitted provider and
probability profile) to the same Call/Entry/Slot/attempt, actual Plan and selected
native profile. Matching profile DATA is not installation or completion authority.
A missing runtime hook refuses before preparation; a late binding refusal retains
the original Unknown/raw cleanup obligation without creating another Entry.

The existing Model `DecodePhysicalResponse` phase parses and admits the original
envelope, scans actual nullable usage/model/ID, maps original aliases, applies
the existing probability validator, and type-admits the answer. No SDK CPU loop
reports parse progress as physical I/O. Parser/scanner/type transitions yield;
the pre-existing finite synchronous alias codec and distribution validator remain
finite synchronous units, not a claim of instruction-level preemption. Their
local work ceilings are not converted into Ledger planning charges or extra
parent Model work. Unknown raw fields remain in the original Artifact; missing
usage/finish/request ID are not filled from SDK defaults or reported rounding.

Raw, decoded/admitted root, mapped wire/parser, typed child and callback borrows
overlap until their actual retirement and must be covered by original funding.
Cleanup-only usage reading selects the same native codec for a stopped original
Unknown/failed response, without replacing that terminal or resending it.
This internal seam's selected tests are isolated Common children and actual
pinned SDK with synthetic fetch/Entry/profile/receipt doubles; they do not prove
actual native Store ACK, complete numeric funding, live Jev or public Named Result.
