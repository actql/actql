# Common inference execution: implementation boundary

Branch: `feat/common-infer-execution`.
Base: `373764e0bd0c100451575cdb0b1a4e90f4e8ce43`.

This is an implementation record, not an inference completion declaration.
The independent acceptance Program and outcomes remain those in
[B's handoff](2026-10-01-infer-keep-handoff.md). No frontend evaluator,
alternative Run owner, model cache, or new wire version is introduced.

## Current handoff status

The one-row public Host handoff is **not ready**. The records below describe
earlier implementation units and their verification, not current acceptance
of the complete inference path.

The current execution owner now adopts classified no-response failures as
keyed outcomes, replays mixed success/failure observations without dispatch,
and retains strict-failure observations through private stopped-execution
reads. Formal durable all-slot evidence, installed policy/dependency admission
and the public Host-to-Named-Result connection are still incomplete. The units
below must not be substituted for those remaining acceptance conditions.

Normal Program preparation now retains the installed ModelTask contract and
its role-specific dependency roots. The runtime input connection uses the
same checked Program owner to execute `Values -> assert_rows` through the
existing bounded Local provider. Its actual `CompletedOutput`, not a raw
Values capture, feeds `bind_infer_completed_input` and bounded INPUT mapping.
The installed deterministic ModelTask provider receives the mapped `text`
role, and the successful capture contains `{reason: null, risk: "high"}`.

The accepted execution now owns the output Relation. Its private capture,
not a caller-authored capture bundle, supplies the checked key, `outcome` and
nullable `value` cells. Import uses the existing bounded session, incremental
value admission and measurement cursors. An exact completion contract retains
the Infer target separately from the adjacent pure prefix; Infer is not added
to AoA. The original checked Result selection transforms that completed output
into the existing publication payload:

```json
[{"id":"a","outcome":"ok","value":{"reason":null,"risk":"high"}}]
```

The one-row fixture uses `quantum=1` and actual macrotask yields while importing
and transforming the result. It verifies one provider call, refuses unaccepted
or foreign-owner output, retains a stable completion identity, and stops during
admission of the nested model value. Output custody prevents model cleanup;
model custody prevents mapped-input and prefix cleanup. Cleanup never dispatches
again. A response returned after cancellation cannot authorize output. Repeated
cleanup is idempotent, and transferred capture material survives execution cleanup.
The provisional output importer preserves logical node/text/work charges;
independent two-row bounds are 26 physical steps, seven live structural slots,
six value nodes, ten UTF-8 bytes and sixteen logical work units. One-short limits
reject, and a 4,096-element array can be cancelled during admission before any
row is sealed. This does not claim incremental Unicode scalar normalization,
vector recheck, or asynchronous provider I/O beyond their current bounds.

The reproducible narrow check is:

```sh
moon build --target js --release src/connectors_builtin_node
node --test scripts/infer-owner-checker.test.mjs
```

This uses normal Program preparation and the common runtime bridge, not the
public Embedded Local/HTTP Run entry. The test owns provider registration
through `clientProgramInstallModelProvider`; it does not assemble internal
execution state. Calls are one for the successful row and zero for empty
input, prefix key failure and prefix cancellation. Same-input replay and
cleanup do not call the provider again. Foreign providers, foreign request
identities, changed keys and reclaimed input are rejected. Model consumers
pin mapped rows and the prefix until physical settlement and cleanup.

This internal replay check is not the versioned durable model capture or
Run replay contract. The fixture's supplied fixed-request CID is likewise
not evidence that the normal Host has derived and admitted a semantic
request. No public Result, response Artifact or Run evidence is manufactured
from this test observation.

The remaining connection belongs to the common inference work:

- Admit the barrier's classification, dependency closure and execution
  envelope under the installed Host authority. Identity alone grants none of
  these permissions.
- Connect that compilation and the model execution to the existing
  `client-dispatch-owner` and publication owner, retaining stop and cleanup
  custody. `local-values-plan.mjs` currently supplies empty model evidence.
- Read the committed Named Result and compare it with the independent row
  expectation before supplying an adoption SHA or Host startup example to B.

### Current checked compilation and call identity

The 0.1 schemas, pins and independent vectors now define effective inputs,
the actual completed input Artifact, typed ordered keys and logical call slots.
The slot excludes responses, captures and its containing Stage Invocation.
Its occurrence is the saved checked Program step, not execution order or a
worker/attempt index. The normative indirect-cycle rule still needs production
dependency-closure admission; the independent cycle oracle is not that owner.

Checked inference compilation now uses the existing Executable Plan, Bound
Invocation Template and Run Definition owners. It
retains the registered inference profile and exact acquisition graph while
keeping the pure input fragment as its AoA identity. This is compilation
support, not installed ModelTask dispatch authority.

Model-containing compilations now reject both the empty source-free Invocation
issuer and the source-only issuer. Having no SourceView inputs cannot erase
the model acquisition. Its final ObservationSet and Invocation must be bound
to verified capture, not issued in advance using an empty observation.

Scoped physical execution derives the input Artifact from its real bounded
prefix completion. A stepped scan wraps the existing export/receipt owner,
preserving its canonical identities and column measurements without retaining
a row-sized payload. Nested admission and measurement consume quantum before
ModelTask dispatch. Cancelling the scan cannot revoke its producer's input;
physical stop and cleanup remain separate. Scalar wire emission and schema
setup retain their existing bounded ceilings; this does not claim that every
Unicode leaf or schema operation is character-stepped.

The preceding narrow verification passed on JS, Wasm and native: identity scan
2/2, completed export 15/15, model execution 2/2, inference Host owner 16/16,
and Run compilation 31/31 on each target. The Node inference bridge passed
24/24, including actual
macrotask cancellation during unused nested input measurement and stable slot
identity after reconstruction. Independently specified scan bounds are 29
steps and 47 workspace slots; one-short failures retain no scan allocation.
The earlier complete specification gate passed; its log is
`_build/model-call-slot-spec.log`. No Linux CI result is claimed for this unit.

The scoped model execution now issues the registered model-invocation evidence
from its own checked response, exact input Artifact, typed key and call slot.
Response and validated-value hashing use bounded wire cursors; each transition
consumes work before returning. Independent Node expectations bind the actual
response/value CIDs, input key, provider identity, request ID, token usage and
observation time. Caller-authored `ModelCaptureBundle` data cannot supply this
execution's evidence. The unscoped fixture path remains a private observation
and does not acquire formal evidence authority.

Cancellation is tested after response admission but before observation sealing,
and after sealing but before output handoff. Neither exposes a completed output;
the latter retains its private observation until cleanup. Cleanup makes no
additional provider call. These are in-process observation/custody tests, not
the required durable-capture stop windows or process-restart replay test.

### Checked observation replay and custody

The common model owner now issues an opaque `VerifiedModelCapture` read only
after its scoped execution has accepted every checked response and its actual
invocation evidence. A matching slot CID, a public `ModelCaptureBundle`, or an
unaccepted execution cannot issue this read. It does not grant egress, durable
Store custody, or Run publication authority.

`client_infer_host.start_replay` prepares the ordinary Program prefix again,
scans its actual completed input, and establishes its new exact call scope.
The shared bounded request-preparation code derives the typed key and formal
slot exactly as for physical calls. Replay additionally checks the task,
fixed request, input Artifact and row count against the checked capture owner.
Changed input and changed ModelTask are rejected with `OutputIdentity` instead
of falling back to a provider. There is no provider parameter or dispatch
alternative in the replay API.

The caller's capture read, the prefix execution, the model replay child and
output consumers have independent custody. Releasing the caller's read after
starting replay cannot reclaim the captured data during the prefix or model
phase. Stop confirmation still precedes child cleanup. Final cleanup releases
the replay read, mapped input and original physical reservations without another
model invocation. This is a reconstruction under a fresh prepared Program in
the same process, not restoration of capture from disk after a restart.

The added acceptance fixtures compare transformed output with the independent
literal row above, reject input and ModelTask changes, reject a released capture,
and cancel replay both during its ordinary prefix and model preparation. For
the one-row replay, the independently derived model work boundary is ten:
one start transition, eight shared request-preparation transitions and one
accepted-capture transition. Nine fails specifically with `WorkLimit`; no
output is issued. Replay makes no model attempt or transfer charge, while its
ordinary prefix, identity traversal and output retain their existing budgets.

Verification of this replay unit passed: `client_infer_host` 20/20 on each of
JS, Wasm and native; `model_execution` 2/2 on each target; the Node bridge 26/26.
The JS runtime build, generated interfaces on all three targets, public API
comparison, `moon fmt --check` and `git diff --check` are the narrow checks for
this code-only unit. The first Node run omitted the pinned `MOON_HOME` and its
fixture freshness check rejected that environment; the rerun with the pinned
toolchain passed all 26 cases. No runtime bundle is committed. No new Linux CI
or pushed-SHA verification is claimed.

### Bounded capture export and encrypted Store custody

The checked model owner now retains the actual raw structured response beside
its validated value and invocation evidence. An opaque capture read can export
the existing `actql-model-capture-bundle/0.1` body through a bounded session.
The first pass hashes the preimage; the second emits provisional chunks with
the bundle self-CID. Only accepted terminal output exposes that identity.
Nested response traversal consumes individual steps and observes cancellation.
Flat invocation evidence has an explicit 16-KiB/1,024-node serialization bound;
it cannot conceal an unbounded response subtree in that step.

The exporter retains its own capture read. Stop confirmation precedes cleanup,
which discards the writer's partial buffer and releases that read exactly once.
The original model owner cannot reclaim its input or observation while export
or caller custody remains. This uses the existing bounded execution and capture
owners, not a second model scheduler or durable execution ledger.

The Node integration independently encodes the expected formal bundle and its
CID, checks the exact full-wire byte ceiling and one-byte-short rejection,
and saves the result using the actual Local publication Store's encrypted
private-evidence and physical-holding APIs. Closing and reopening that Store
preserves authenticated, exact-bound bytes. A directory-sync failure during
confirmation retains the capture owner; retry confirms the same holding without
another model call. A different wire is rejected. A macrotask cancellation
during a 512-element response export produces no accepted bundle CID.

This unit proves bounded serialization and durable authenticated bytes, not
restoration into a verified model replay owner after process restart. Store
confirmation is physical custody, not inference authorization or publication.
The serializer's own byte/node/work bounds also do not replace admission under
the global Host execution envelope. Transitive dependency admission, installed
ModelTask policy, restored replay and public Named Result publication remain
required before B receives an adoption-ready SHA.

Verification passed on JS, Wasm and native: `client_infer_host` 22/22,
`encode_core` 37/37, `model_execution` 2/2 and `run_publication` 179/179 on
each target. The Node inference bridge passed 28/28, and the two existing
private-evidence Store cases passed. The JS runtime build, generated interfaces,
public API comparison, formatting and diff checks cover this code-only unit.
No runtime bundle is committed; no push or Linux CI success is claimed.

The persistence-only unit above did not restore its saved record. The next
unit below adds authenticated Store restoration and checked component replay.
Installed public Host registration and committed Named Result retrieval still
remain unfinished. The fixture execution policy is identity-only material,
not public policy admission. This branch is not an adoption-ready handoff to B.

### Restored capture validation and component replay

The existing model capture bundle schema is now registered with the common
generated protocol reader. Its canonical body, version and schema pin are
unchanged. Structural admission verifies the outer self-CID, and each record
separately verifies its invocation-evidence self-CID and record references.
Neither admission nor a matching CID grants model execution authority.

The restoring path prepares the ordinary Program prefix and its actual
CompletedOutput again, derives the fresh typed key and fixed request, and
checks ModelTask, input Artifact, slot, request, key and model selector against
the saved record. Raw response conversion and normal typed recheck advance
incrementally, including array, object and vector members. Decimal and
timestamp leaves use the existing scalar admission rules, not a second model
decoder. The common model owner then recomputes response/value identities and
invocation evidence; that exact evidence must match the saved record before
acceptance. There is no provider argument or dispatch fallback in this path.

Saved reads have independent caller, Host and model-child custody. Releasing
the caller's read cannot invalidate a replay already preparing its prefix.
Cancellation during nested reconstruction exposes neither output nor capture;
stop confirmation precedes cleanup, which releases reads and builders without
another Compute or model invocation. Replay reserves no new model attempt or
transfer, while its ordinary prefix, validation and output remain charged.

The actual encrypted Local Store test now reclaims the original execution,
closes the Store, starts a fresh Node process, authenticates and confirms the
saved physical holding, and prepares and replays the Program there. It compares
independent literal output rows and the original invocation evidence. No model
provider is installed in that process. Mutation cases independently reseal the
outer bundle and reject changed slot, request, task, Artifact, key or response;
an unsealed inner record is rejected even when the outer CID is valid. A
512-member response is stopped during incremental reconstruction after real
macrotask yields. The original physical provider remains at one call.

Verification passed on JS, Wasm and native: `canonical_json` 455/455,
`value_admission` 135/135, `client_infer_host` 24/24, `model_execution` 2/2,
and `run_publication` 179/179 on each target. The Node bridge passed 30/30;
the protocol generator and its six tests passed. Generated public interfaces,
API comparison, formatting and diff checks cover this implementation unit.
No runtime bundle is committed. No push or Linux CI result is claimed.

This proves component replay after process restart, not public Run replay or
Named Result publication. Protocol parsing is a document operation under
installed byte/node/depth ceilings; this does not claim unbounded incremental
JSON admission. Scalar text and metadata retain their bounded leaf operations.
Serialized Ref objects do not mint issuer authority. Production transitive
dependency admission, installed policy/envelope admission, durable handling of
unknown physical outcomes and the public Run/publication connection remain.

The normative ObservationSet must bind captured model attempts and adopted
outcomes. Its current closed machine schema has no model-capture reference
field. The source-evidence and input-Artifact fields must not be repurposed
for that distinct identity domain. A coordinated contract correction is needed
before the final model-containing Invocation can be issued; the existing
empty/source-only issuers continue to reject it.

### Existing dispatch supervision and physical stepping

`adapters/host-node/infer-operation.mjs` adapts the existing MoonBit execution
to the installed `client-dispatch-owner` cleanup interface. Opening executes
no model callback. The dispatch callback retains the physical owner before
its first advance. One stepping promise drives either the installed provider
or an authenticated, Store-confirmed saved read; replay has no provider
alternative. The adapter yields real macrotasks between bounded advances.

MoonBit reports the typed terminal poll and physical stop state. JavaScript
does not derive completion from row counts, cancellation delivery or absence
of output. Physical stop and reclamation are separate: independent output
or capture reads can keep cleanup pending after execution has settled. Close
retains its first promise, while cleanup retries call only the existing owner
and never restart inference. Typed model failures remain the cause of the
existing `MoonBitHostFailure`, without a new public error classifier.

The component integration uses the normal checked one-row Program and actual
ModelTask callback under the existing dispatch supervisor. Two output readers
retain the same completed output independently. A held capture makes close
and drain fail, and releasing it permits drain without a second run or model
call. A model response schedules cancellation on a real macrotask before
output handoff; the test verifies no completed output or capture, eventual
physical stop and final cleanup. Invalid opening and closing before the first
advance perform no model dispatch. The encrypted Store reopen and fresh-process
replay tests now drive this same physical adapter as well.

Verification passed: inference Host owner 24/24 on each of JS, Wasm and native;
Node inference bridge 35/35 and existing dispatch-owner regressions 13/13.
The release bridge build, regenerated interfaces, API comparison, Node syntax,
formatting and diff checks cover this unit. No ignored bundle is committed.
No push, Linux CI or public Named Result acceptance is claimed.

This adapter is not yet installed by `embedded-local.mjs`. Its component
fixtures use identity-only policy dependencies, not a runnable public policy.
The pending ObservationSet contract correction, production dependency and
policy admission, public startup registration, and final Result publication
remain necessary. The supervisor integration does not supply an adoption SHA
or a completed public Host startup example to B.

## Checked compilation prefix

### Owned inference template material

The checked Infer acquisition graph now feeds the existing Bound Invocation
Template and execution-material owners. Its template requires the registered
`actql-infer/0.1` barrier schema, not the authored ModelTask contract as a
profile substitute. Program, parameter, environment, opaque-binding and pinned
compiler identities come from the original prepared owner. The existing
Result-plan issuer supplies the complete named Result map; no new Result
identity or publication path is introduced.

An equal serialized Program with a different owner cannot use this graph.
Saved material is reissued under the checked graph and current manifests;
changed Template CIDs, missing Result names and changed Program bodies reject.
Strict mode and empty input still require the Infer profile. Existing pure
task templates continue to emit their empty profile list.

These are compilation prerequisites, not an admitted executable Plan. The
private graph's limit and egress references still lack admitted bodies, and
the template deliberately retains `source_evidence: unbound`. It supplies
neither future model evidence nor a fabricated call-slot identity. The normal
Client Run compiler/dispatch/publication connection and B's committed Named
Result acceptance remain unfinished. The canonical call-slot definition
requested in the working report is still awaiting approval and unchanged.

The Node bridge exposes this material under the same ordinary Program
preparation. Its component test independently hashes the template, checks the
registered profile, original input mapping and Result name, and refuses an
equal foreign owner. It does not construct internal preparation state or
claim a public Host startup example.

All 30 `run_publication_host` tests passed on each of JS, Wasm and native,
including the three new Infer material tests and existing pure compilation
regressions. The rebuilt Node component bridge passed all 21 tests. Generated
interfaces were refreshed from the integrated source; formatting, JavaScript
syntax and whitespace checks passed. Complete CI jobs, Linux CI, packed
Embedded Local/HTTP acceptance and committed Named Result reading did not run.

### Owned item-capacity compilation

The private Infer graph retains item-capacity material derived from its actual
checked Program. Applicable input row proofs are reidentified under the same
Unit owners and bound to the Infer occurrence through the registered
`actql.bound.infer-distinct-keys` law. Host and installed ModelTask ceilings
remain distinct candidates. Literal and supplied-parameter guards retain their
actual declaration owner; the minimum is not inferred from a successful model
execution or an observed input count.

Preparation uses an explicit work/encoding budget and happens during graph
compilation, not inside bounded execution start. Foreign Program owners,
non-Infer steps and insufficient preparation work do not issue this material.
The normal Program fixtures independently expect one key from one input row,
two from three rows under the ModelTask ceiling, one under the Host ceiling,
and zero for empty input. They also check the guard witness and its supplied
parameter value.

This is not a complete executable inference Plan. Its existing item candidates
do not admit a language-ceiling body, retry/backoff/media dependencies, the
physical envelope or current egress authority. In particular, the barrier's
`limits_cid` is not replaced by the item-limit CID. The private graph retains
the checked material for subsequent Plan fact and envelope compilation.

The public Host handoff remains unavailable. Formal model evidence requires
the missing canonical call-slot preimage to be resolved; the current private
capture must not be relabeled as that evidence. A still owns the remaining
Plan, common dispatch-owner and publication connection. B cannot start packed
INFER acceptance from the component bridge or a placeholder evidence CID.

Focused capacity/prefix/graph tests passed 7/7 on JS, Wasm and native. The
rebuilt Node bridge passed 19/19, including one actual provider call for the
successful row and zero calls for rejected item limits. The first Node run
omitted the pinned toolchain environment and failed its fixture precondition;
the complete rerun with `MOON_HOME` and its `bin` on `PATH` passed. Generated
interfaces were refreshed from source. These results are not public Host,
committed Named Result, complete core-gate or Linux CI evidence.

### Bounded mapped-request preflight

The model owner prepares every mapped request before its first provider call.
Key and private slot encoding, input collection and structured input measurement
advance through the existing incremental wire cursor. A later row that exceeds
the byte ceiling rejects the execution with zero calls, even when the earlier
row fits. The ceiling is read from the same prepared Program's checked Host
policy; a physical envelope can tighten it but cannot widen it.

Each slot reserves request and response retention together before preflight.
Cancellation retains mapped-input custody and those reservations until physical
stop and cleanup. The normal Program test cancels a 1,024-element request from
an actual JavaScript macrotask during incremental encoding, before any provider
call, capture or completed output. Cleanup releases retained and reserved
charges without refunding attempts or dispatching again. Provider callbacks
observe all requests prepared before the first call.

Independent boundaries are 16 mapped-input JSON bytes for `{"text":"hello"}`,
48 bytes for `{"text":[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]}`,
and 17 or 50 model transitions respectively for their two-field responses.
Exact and one-short cases check typed failures, provider counts and custody.
Nested response work is now `2 * n + 18`, including request preflight. With
the fixture Host's 1,000-byte request and 65,536-byte response ceilings, the
one-row reservation is 66,536 bytes. The old response-only bounds below are
historical results from the preceding implementation unit, not current limits.

Focused checks passed on JS, Wasm and native: twelve `client_infer_host` tests,
two `model_execution` tests and seven Infer-focused `run_publication_host`
tests per target. The rebuilt Node bridge passed all 21 tests, including both
request and response cancellation through actual macrotask delivery.

These measured bytes describe mapped-input JSON, not an exact physical adapter
request, prompt/tokenizer/media plan, semantic request or model-egress authority.
The existing scalar encoding and private identity bounds remain unchanged.
The private slot spelling is not a registered public call-slot identity.
Executable Plan admission, common Run dispatch, formal captures/replay and
committed Named Result reading still need their production connection. This
unit supplies no adoption-ready public Host SHA or Linux CI evidence.

### Historical response-admission boundary

The model owner now reserves one attempt per resume, completes all slot
reservations before dispatch, and validates a returned value with the existing
incremental runtime admission cursor. Pending responses remain private and
owned until validation succeeds or cleanup completes. Each transition consumes
cumulative work; a one-short work limit cannot accept an incomplete response.
The actual provider-reported model, request ID, token counts and observation
time are retained rather than replacing them with the authored selector.

Independent one-row bounds are nine model transitions for the two-field
response and `2 * n + 10` transitions for a response containing `n` array
elements. Exact and one-short work/value-node cases preserve one provider call.
A 4,096-element response stops during child admission after an actual macrotask
cancellation, before capture or output completion. Cleanup releases the existing
ledger reservations and input use without dispatching again. A two-row attempt
limit of one rejects during reservation with zero provider calls and retains
partial reservations until cleanup. Read-only ledger observations establish
that transfer, retention, execution and held charges are zero after reclamation;
the cumulative attempt count is not refunded.

The focused checks passed on JS, Wasm and native: eight `client_infer_host`
tests and two `model_execution` tests per target. The rebuilt Node bridge passed
all 19 `infer-owner-checker` tests. Public interfaces were regenerated, and
formatting and whitespace checks passed. These are component results, not
public Host or Linux CI acceptance. Provider callbacks, final capture copying
and scalar admission retain their existing bounds; this change does not prove
fully asynchronous provider I/O or every possible non-interruptible operation.
The capture JSON and same-owner replay remain provisional, not formal versioned
Run evidence or durable replay. The public handoff status above is unchanged.

### Dispatch item admission

The composed execution reads `max_infer_items` from the original prepared
Program's checked Host capacity policy. An adapter envelope may tighten this
ceiling, never widen it. INPUT lowering retains literal or parameter-bound
`max_items` under the exact parameter declaration owner, and the common model
owner checks that guard after key admission but before attempt reservation or
provider dispatch. Invalid positive-count bindings retain their typed cause
and authored guard location.

Normal two-row Programs exercise an independently chosen exact boundary of
two slots and a one-short boundary of one slot. The short Host ceiling,
literal guard and bound parameter guard cause `Model(ItemLimit)`, zero
provider calls, no completed output, and idempotent cleanup. This is physical
item admission, not the full resolved-limit witness closure, adapter preflight
or model-egress authority of an executable inference Plan. The public Host
handoff remains unavailable until those and committed publication are connected.

Focused item-admission checks passed on JS, Wasm and native: four
`client_infer_host` tests, four `infer_inputs_wbtest` tests and two
`model_execution` tests per target. The rebuilt Node bridge passed all 18
`infer-owner-checker` tests. Formatting and whitespace checks passed.
These results do not cover public Run acceptance, committed Named Results,
Linux CI or an adoption-ready handoff to the Frontend owner.

### Prefix compilation

Compilation and bounded execution now share
`run_publication_host.client_infer_prefix_owner`. The initial source-free,
single-task shape selects an actual Infer's adjacent Relation producer from
the original bound Program; wrong task, wrong step and non-Relation inputs
do not select a prefix. The fragment compiler prepares only those pure steps
and seals their actual Relation output contract. Ordinary task compilation
retains its existing full-sequence preparation and validation.

`issue_prepared_client_infer_prefix_fragment` does not issue an Executable
Plan or claim to support the acquisition. The original whole-task compiler
still rejects Infer as a pure kernel. The narrow fixture compares this
fragment with an independently prepared pure Program: their pipelines,
logical CIDs and output contracts agree. Strict versus outcomes mode does
not change the adjacent AoA fragment. Two prefix steps fit a two-step
preparation limit; one step fails with `SequenceLimit`. Invalid task/step,
encoding limits and accidental whole-task AoA compilation are also refused.

The next connection is the acquisition node and its execution envelope, not
another Relation evaluator. `client_task_plan_graph` currently assumes one
AoA node per task; executable Plan and invocation-template issuance currently
emit empty required-profile lists. These sites must bind the installed model
contract and acquisition inputs before the existing Client dispatch owner
can start this Program. The pinned barrier manifest now contains the
inference barrier declared by Language's typed-boundary table; its presence
does not admit retry, prompt, media or egress dependency bodies. This remains A's
common integration work, not an external B or C implementation blocker.

The public Host handoff is still not ready. Prefix identity and component
output-export checks do not prove Run acceptance, committed Named Result
reading, current egress authority or versioned capture/replay.

Narrow prefix and existing Carrier task-compilation tests pass 4/4 on each
of JS, Wasm and native. The normal Program/model bridge passes 12/12, including
the prefix identity comparison, and Node assembly tests pass 8/8. The regular
and RelA-only assembly freshness checks pass. Public interface regeneration
is checked separately; complete CI jobs and Linux CI have not run for this
implementation unit.

These are unfinished integration work, not an unspecified Engine redesign
or a claim that C must implement a replacement Run state machine. The old
synchronous fixture helper has been removed: it captured Values directly,
skipped the real asserted input target and returned observation JSON rather
than a public Result. Only the full Node bridge imports the model kernel;
the RelA-only bridge keeps its existing dependency separation.

The preceding input unit passed 19/19 on each target, seven normal Program/model
bridge tests and eight Node assembly tests. The subsequent output unit is
verified separately; the committed SHA and commands are recorded in its commit
and the working report. Output import, original admitted output, completion,
Infer preparation and model tests passed 22/22 on each target. The additional
JS exact fixed-input test passed, the normal Program/model bridge passed 11/11,
and Node assembly tests passed 8/8. Complete CI jobs, Linux CI, durable
capture/replay and committed Named Result reading are not established by these
component tests.

## Object and property execution

The existing checked expression forms now reach shared typed lowering and
Relation evaluation. Object members follow the contract's canonical UTF-16
field order. Property access carries a checked field ordinal; a nullable
receiver returns typed NULL without treating missing fields as NULL.

Ordered reference evidence includes every demanded child, with RFC 6901
escaping and UTF-8 pointer accounting. Closed-object construction uses the
existing immutable value builder and logical root owner. Temporary byte and
workspace reservations precede append; partial builders and roots remain
owned until completion or cleanup. Work is not refunded on cancellation.

Constructed objects and borrowed aggregate operands of object/property
expressions use the existing resumable measurement cursor. Reusing an exact
private root measurement avoids rescanning an immutable operand but retains
its full semantic work charge. This is not a claim that every existing
expression or scalar string operation has been changed.

The standard retained Host fixtures publish the KEEP-shaped object and its
filtered property projection, then read all three Named Results through the
real publication Store. Both consumers use the ordinary checked Relation
task path. Input rows and expectations are authored independently:

```json
[
  {"id":"a","note":"urgent","assessment":{
    "input_key":{"id":"a"},"outcome":"ok",
    "value":{"risk":"high","reason":null}}},
  {"id":"b","note":null,"assessment":{
    "input_key":{"id":"b"},"outcome":"failed:refusal","value":null}}
]
```

Filtering `assessment.outcome = 'ok'` and
`assessment.value.risk = 'high'` yields `[{"id":"a","risk":"high"}]`.
Values supplies already captured-shaped rows in these tests. It does not
stand in for inference dispatch, acquisition capture, or replay evidence.

Minimal common Host regression:

```sh
moon build --target js --release \
  src/connectors_builtin_node src/connectors/duckdb/conformance
node --test --test-name-pattern='retained object projection' \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs
```

## Remaining common inference implementation

| Boundary | Current limitation | Required implementation |
| --- | --- | --- |
| ModelTask admission | Explicit Program preparation binds the admitted task inventory; dependency and execution preflight remain absent | Resolve prompt, retry, backoff and attachment dependencies before execution |
| Checked operation | Pipeline and topology preparation retain the typed infer owner, INPUT mappings and produced keys; complete Program execution remains refused | Close acquisition capacities, success refinement and runtime obligations without lowering acquisition as pure computation |
| Barrier execution | The private bounded owner connects the real checked Relation prefix to a registered ModelTask; standard Host admission has not installed it | Admit fixed request and dependency bodies, adapter plans and egress before dispatch; bind formal slot and attempt evidence |
| Capture and replay | Existing publication code admits model evidence, but no inference owner produces it | Seal classified slot outcomes and real response/issuer evidence; replay captured observations without provider calls |
| Public Host | The current dispatch owner opens source-free or SourceView acquisition configurations | Connect the typed inference barrier to the existing Run admission, dispatch and publication owners; do not add a second Host state machine |

A owns the common ModelTask and infer implementation above. B retains parser,
source construction, independent Programs and packed Local/HTTP acceptance.
Any necessary Host adapter connection must use C's existing dispatch owner.
No dependency on an unspecified future Engine redesign is claimed here.

The independent Values fixture declares `key: id`, but Values itself does
not establish candidate-key evidence in the current checker. Its unique
literal rows are not a compiler-proven key. Acceptance input needs an
existing key proof, for example an `assert_rows.unique_by` producer or a
keyed input declaration. The expected model and Result values stay unchanged;
neither the frontend nor the infer owner may invent that proof from a name.

`run_publication/captured_run_issuance.mbt:captured_model_evidence` and
`run_publication/evidence_chain.mbt` already provide model evidence checks;
they must not be replaced by a new capture ledger. Existing
`actql.model_task/0.1` and `actql-model-slot-capture/0.1` bodies remain the
contract baseline. Checker acceptance will not be reported as executable
inference. The first runtime handoff can cover one real Host-dispatched row
while the remaining KEEP and replay acceptance is developed in parallel.
Capture and replay remain requirements for completing the inference unit.

## Bounded physical composition

`client_infer_host` now composes the existing Local prefix, mapped input,
ModelTask session and incremental output importer under one physical owner.
It retains the original prepared Program rather than accepting finished
input rows. Each advance runs one child only, even at a phase transition;
work accumulates across children and is never reset with a child cursor.
The package is registered in the full Node bridge only. The RelA-only
bridge does not import it or the model kernel.

Completion has an explicit final yield before output handoff. Cancellation
at that yield or during a response callback prevents output acquisition.
Reentrant advance is rejected, and cleanup waits for physical settlement.
Two output uses retain independent custody: releasing one cannot invalidate
the other, and cleanup does not dispatch another model call. This physical
owner does not replace Run admission, dispatch journaling or publication.

The new normal-Program fixtures pass three tests on each of JS, Wasm and
native. They cover the actual prefix, one provider invocation, independent
output uses, prefix cancellation and cancellation at the final yield.
Node tests also yield through `setImmediate` between advances; they do not
claim cancellation delivery during a synchronous foreign provider call.
Admission data is projected from existing independent vectors, formatted
with the pinned formatter, and checked for freshness by the Node suite.
Expected values and finite poll ceilings are authored separately.

This remains a component connection. The public Host has not yet derived
and admitted the fixture's fixed request, produced formal model evidence,
or committed its Named Result. B must not adopt this commit as the requested
public Host execution SHA. Durable capture/replay and KEEP acceptance remain
unfinished; the provisional capture tests do not discharge those contracts.

## Mapped-row preparation

`execution_relation/infer_preflight.mbt` binds captured or cell-readable
completed rows to the exact checked schema, bound invocation and input target.
Its shared bounded session prepares all keys before evaluating INPUT mappings.
It reuses the Relation merge sorter and resumable typed key comparator, rejects
duplicate and invalid keys, and visits rows in canonical typed key order.
All mappings share cumulative control, workspace and existing logical root
budgets. Only declared input roles are returned; unrelated columns are not
model inputs.

Key scanning, sort initialization, comparisons, snapshots and mapping
transitions run inside resume. Cancellation preserves the borrowed input;
accepted mapped rows have separate cleanup custody. The completed-input path
resolves physical column positions from the existing completion rather than
assuming that its stored columns are in checked-schema order. A foreign
invocation, schema or target cannot substitute for the exact binding.
Detached expression roots remain with preparation during receiving-contract
validation, then transfer to the accepted mapped-row owner. Failure and
cancellation release pending roots without refunding work. Preparing a second
row or role does not reset logical work or live-value accounting.

This is row preparation, not a model dispatch plan. Its `max_items` is a
preparation capacity ceiling, not the final resolved Contract/Host/author
limit. It does not yet admit prompt/retry/media dependencies, classification,
authority, exact adapter requests, tokenizer results or token/cost reservations.
Expression evaluation enforces intermediate value, live-root and work limits
through the existing owner. Existing scalar text admission/rechecking
can scan a scalar synchronously; the long-prefix test establishes bounded key
comparison, not universal boundedness of all input validation. These gaps must
not be hidden by treating successful preparation as permission to dispatch.

The affected preparation, mapping, object/property and shared-sort regressions
passed 24/24 on each of JS, Wasm and native. The complete `execution_relation`
JS suite passed 1,075/1,075. Tests include duplicate/NULL keys, an independently
derived one-row work bound of 61 and workspace peak of 13, exact/one-short
limits, cancellation at four preparation phases and during a long-prefix
comparison, borrowed-source availability, empty input and final cleanup.
Additional tests fix two scalar mappings at 16 logical work units and 16
live encoded bytes, check the one-short limits, and reject a 30-byte demanded
intermediate object under a 29-byte ceiling even though the final scalar fits.
These are common-core tests, not timer-delivered Host cancellation or model
capture/replay. No public Host inference adoption SHA is available yet.

There is not yet a SHA on this branch at which B's entire independent INFER
Program executes. Its successful packed acceptance remains pending. The
object/property tests are separate partial evidence, not a completed infer
unit. No external model service has been called.

## Local verification of the expression change

The pinned MoonBit toolchain and Node 22 were used. The final source passed:

- Object/property execution regressions on JS, Wasm and native: 8/8 each.
  These include nullable receivers, nested construction, independent exact
  and one-short work/live/value/workspace bounds, cancellation during
  construction and measurement, and a large borrowed object under coalesce.
- Complete `lowering_relation`, `execution_relation` and `query_program`
  JS tests: 1,366/1,366.
- Rebuilt standard retained Host object/property tests: 2/2. All three
  Named Results were read and compared; normal owner cleanup left no retained
  resources or execution reservations.
- Public interfaces matched JS/Wasm/native and the regenerated interface.
- `moon fmt --check` and `git diff --check` passed.

Before the final nested-context adjustment, the same three package suites
also passed 1,366/1,366 on Wasm and native. The final adjustment was rerun
through the eight affected execution regressions on all three targets,
the complete JS package suites, and both Host cases. This earlier broader
run is not reported as a full final-source Wasm/native suite.

The initial large-object fixture had a missing closed-contract flag and
used a small test parser limit; correcting fixture admission resolved those
test setup failures. Full lint/Core/DuckDB jobs, successful packed inference,
Linux CI and external provider acceptance have not been run for this unit.

## ModelTask contract admission

`check_environment/model_tasks.mbt` now checks every supplied ModelTask,
including unused declarations. It recomputes the task self-CID and both
embedded schema CIDs, reads checked non-null closed input/output objects,
validates generation and data handling, and rejects duplicate task selectors.
Nullable object members and absent optional limits are preserved. Lookups
retain the exact admitted environment; a same-CID foreign member is not an
interchangeable owner. Unknown classification never satisfies the task's
accepted-classification test. That test is compatibility, not Host authority.

`check_environment/model_execution.mbt` reads the registered
`actql-model-execution-contract/0.1` body. It checks canonical bytes, self-CID,
the exact admitted task reference and all six finite execution ceilings.
Retry-classification, backoff and media contract CIDs remain unresolved
dependencies. Reading this body does not authorize retry, media access or
model dispatch. Preparation uses cumulative body, value-contract and work
limits; subtree hashing and typed reconstruction are charged separately.

The task and execution-contract identity fixtures use independent Node crypto
vectors. Regression coverage includes missing required fields, stale inner
CIDs under a freshly hashed environment, duplicate selectors, unsafe or
invalid settings, exact/one-short preparation limits, closed object contracts,
nullable success members and foreign environment handles.

This is a foundation for the shared inference owner, not a completed
acquisition path. The Program checker still refuses `infer` until checked
execution, capture and replay are connected. No B fixture was marked as a
successful packed inference, and no external model was called.

The complete `check_environment` package passed 201/201 tests on each of
JS, Wasm and native after adding the readers and regressions. After the
final typed-reconstruction precharge, all 201 JS tests and the nine affected
regressions on Wasm and native passed again. `moon fmt --check` and
`git diff --check` passed. The generated public interface passed
`scripts/check-moonbit-api.mjs` across JS, Wasm and native.
Full affected CI jobs and Linux CI remain unverified for this unit.

## Typed inference binding

The checked inference owner binds the exact admitted ModelTask, complete input
schema, candidate-key witness and typed INPUT expressions. It requires all
and only the closed task input roles, checks assignment compatibility and
retains expression validation obligations. Qualified Relation scopes use the
existing schema and expression scope rules, not flattened field names.

An explicit key must equal a whole non-null scalar candidate tuple. Subsets,
supersets and repeated components are rejected. Authored tuple order remains
a separate sidecar from canonical schema order. Omission requires a unique
candidate tuple, including alias alternatives; duplicate witnesses for the
same tuple remain retained rather than creating false ambiguity. Evidence
from an equal-shaped but independently admitted input is rejected. The
original witness keeps its producer and pending runtime validation obligations.

The output schema contains only the selected key fields and fixed outcome
and value roles. The success object retains its original child nullability;
only the outer value becomes nullable for failure outcomes. This schema alone
is neither a produced-key proof nor an outcome-dependent refinement proof.

`relation_typing/check_count_value` exposes the existing count rule for the
infer author guard. It retains the exact parameter declaration owner and
deferred positive-safe-integer validation. No separate parameter parser,
resolved limit or Host authority is invented. Authored minimum classification
and result mode are likewise retained without granting model egress.

The final `infer_typing` suite passed 8/8 on JS, Wasm and native. The unchanged
`relation_typing` suite, including the new shared count-guard regression,
passed 274/274 on each target before the final qualified-scope test was added.
These are typing and admission tests, not model dispatch or packed acceptance.
Complete Program closure, barrier preflight, call execution, capture, replay and
the existing Host dispatch connection remain unfinished. No external model
service has been called.

## Shared INPUT lowering and evaluation

`lowering_relation/prepare_infer_inputs` now prepares each admitted INPUT
mapping using the existing expression lowerer. Relation and acquisition
bindings share one implementation, including profile admission, typed object
fields, checked property ordinals, source locations and cumulative limits.
No second expression evaluator is added.

The infer owner retains its exact parameter declaration owner. Binding checks
use the same helper as ordinary Relation preparation: an equal-shaped foreign
declaration or missing required binding cannot substitute for it. Preparation
charges input entries, field resolution and expression work against one
budget rather than resetting the allowance for each role. The returned owner
does not admit call slots, classification, adapter transport or model access.

The mapped field, nested object/property and nullable parameter fixtures use
the existing resumable expression execution. Independent expectations cover
the existing 0.1 expression wire, string and NULL values, exact/one-short
preparation work, a foreign binding owner, and cancellation without destroying
the caller-owned input. These are input-expression tests, not a model call,
all-request preflight, capture or replay.

Verification of this source change:

- Complete `infer_typing`, `lowering_relation` and `execution_relation` JS
  suites: 1,294/1,294.
- Affected infer, parameter binding, expression lowering and object/property
  execution regressions: 38/38 on Wasm and 38/38 on native.
- Public interfaces regenerated from the integrated sources on all three
  targets; formatting passed.

## First runtime handoff

B's committed connection audit is
`0996714dfa283c428d9feb1e77f869ab94f9cd98`,
`docs/reviews/2026-10-01-infer-owner-connection-readiness.md` on B's branch.
It was inspected without adopting or modifying B's source or expectations.

The first adoption SHA must run the one-row INFER through the real public
Host. It will include a reproducible startup and deterministic physical
provider registration example, exact dependency bodies, input key admission,
finite limits, and an explicit list of unsupported forms. A standalone typed
owner or an injected finished Result does not meet that handoff condition.

The four remaining connections are ordinary Program inference admission,
produced key evidence for KEEP, physical ModelTask dispatch under the current
Host owner, and capture/replay with no replacement model execution. The first
Host connection can be handed off before the complete KEEP/replay matrix,
but those unfinished guarantees must remain visible. There is still no
adoptable full-Program execution SHA or public model registration example.

## Produced inference key evidence

The checked inference implementation now lives alongside the existing key
producer owners in `relation_evidence/infer_check.mbt`. `infer_typing` delegates
to that same opaque owner through a thin facade; it has no second checker.
Its type aliases expose the underlying shared evidence types. This dependency
placement allows the output key to retain the exact checked infer producer,
rather than reconstructing an operation from its source, schema or CID.

`infer_result_keys` preserves only the selected tuple, including its authored
order, under the existing conditional `ValidateKeyProducer` obligation. The
original input witness remains an explicit dependency with its physical key
validation obligations. The output key is neither an input declaration nor
an assertion that any model calls, captures or publication have completed.
The eventual execution owner must fulfill the input and producer obligations.

The new KEEP join regression consumes this produced key through the existing
`select_join_key` boundary. It verifies exact producer and input dependencies,
fixed field names, exact/one-short metadata budgets, and rejection of the
original input key or another infer's equal-shaped output key. It does not
yet execute the ordinary Program or prove a runtime one-to-one join.

The complete `relation_evidence` and `infer_typing` suites, plus the mapped
input execution regressions, passed 32/32 on each of JS, Wasm and native.
The first test version incorrectly expected key selection to return the same
outer witness allocation. Selection legitimately projects a witness; the
correct regression checks the unchanged exact producer and records owners.
No production admission check was weakened to resolve that fixture error.

## Ordinary Program topology

Program topology preparation now accepts an explicitly admitted ModelTask
inventory. INFER retains its exact input edge, unique alias, checked INPUT
expressions, parameter declarations, source locations and produced key. KEEP
joins select that evidence through the existing join boundary. The output
order witness is canonical typed key order, not source or provider order.
When local environment inputs are supplied, an equal-CID foreign task
environment is rejected rather than substituted for their owner.

This preparation does not certify full Program execution. INFER has no pure
operation profile or pure obligations; its acquisition obligations still need
an execution owner. Pure AoA lowering rejects the infer step explicitly, and
core contract closure reports `UnclosedModelAcquisition`. Static publication
policy does not invent model provenance. These refusals remain until real
dispatch and capture are connected.

The pipeline, stage topology, inference typing and mapped-input execution
suites passed 415/415 tests on each of JS, Wasm and native. The fixed pipeline
corpus was regenerated from its source, and its Node tests passed 2/2. These
are preparation and expression checks, not public Host INFER acceptance.

## KEEP projection connection

B's `infer-keep/kept.expected-program.json` at `0996714df` puts expression
objects such as `{"join_field":{"side":"right","name":"id"}}` in
`join.select`. The current common grammar requires qualified field strings
such as `"right.id"`. A correctly keyed INFER followed by the string form
passes topology preparation; the expression form reports `Join(InvalidBody)`.
The regression preserves that grammar rather than widening it for one
frontend. B owns the source-construction correction; its independent expected
Result values are unchanged. A first KEEP-free Host example can proceed
without waiting for that correction.

## Outstanding executable connection

`client-dispatch-owner.mjs` currently opens source-free computation or the
existing SourceView acquisition path. ModelTask dispatch must join that Run
owner without impersonating a SourceView. The checked DAG currently owns
pure prepared task sequences and captured SourceView roots, not a typed
mid-pipeline model barrier. All mapped requests, keys, finite adapter plans
and reservations must be ready before the first physical call. The existing
model capture and publication evidence checks remain authoritative.

There is still no SHA that runs the requested one-row public Host INFER,
no executable provider registration example, and no capture/replay completion
claim. The foundation commits are not an adoption handoff for B.

## Inference barrier graph compilation

The compiler now selects the same checked pure prefix used by bounded input
execution, admits the execution contract against that exact installed
ModelTask, and emits an `acquisition_barrier` rather than an AoA Infer opcode.
The new `ClientInferPlanGraph` is private compilation material, not a Run
admission, ModelTask dispatch ticket, or completed output.

The graph binds the pure input fragment, receiving and producing Relation
contracts, canonical bound mapping expressions, authored key tuple, outcome
mode, execution contract, and referenced limits and egress requirements.
Result roots use the actual model-output port; partial projections reuse the
existing checked Result transformation. A fresh installation of an equal
ModelTask CID cannot substitute for the checked owner.

The already-declared inference barrier had no registered machine body. Its
closed body reuses the existing model-outcome Plan fields, adds the adjacent
input fragment identity, and uses the barrier self-CID field. This fills a
structural contract gap on the existing 0.1 baseline; it does not add source
syntax or change model outcomes. The production registry, compiler manifest,
normative owner references, generated metadata, and dependent Values Run
vector move together. The historical Values vector is retained; the current
Run CID is recomputed from an independent, hand-assembled preimage.

The graph tests intentionally use identity-only retry, limits, and egress
dependencies. Those pins are not executable Host configuration. Their bodies,
current classification and authorization, and finite adapter preflight still
need admission before the compiler material can enter a runnable Plan.

The completion boundary now asks lowering to verify the exact Infer output
binding instead of traversing a generic frontend payload in the execution
engine. The backend semantic boundary gate remains unchanged.

The next required connection is the admitted inference profile in the common
Executable Plan and the existing Client dispatch owner, followed by actual
model observation evidence and committed Named Result publication. There is
still no adoption-ready public Host SHA or provider startup example for B.
The provisional capture/replay tests do not establish durable Run replay.

The barrier, prefix binding, Values identity, ModelTask, and execution-contract
fixtures pass 14 tests on each of JS, Wasm, and native. The normal Program Node
bridge passes 13 tests, and the independent manifest/Values vectors pass six.
The unchanged backend semantic-boundary gate passes 49 tests. Full and
RelA-only Node assembly freshness checks pass.

The specification gate was interrupted while running the existing resource
audit mutation suite after the preceding specification and boundary checks
passed. It has not completed; no full specification-gate or Linux CI success
is claimed for this compilation unit.

## Adopted model slots in ObservationSet

The approved 0.1 correction adds optional `model_slot_capture_cids` to every
embedded ObservationSet schema. INFER requires the complete adopted-outcome
inventory, including failures, in saved logical occurrence order followed by
canonical typed-key order. Zero-key INFER uses an explicit empty array.
Non-INFER omits the field and retains its existing canonical preimage.
Successful-response `model_capture_bundle` identities are not substitutes.

The generated protocol parser now also admits the existing Stage-owned
`model_slot_capture` schema, without defining a second copy. Structural
binding checks the exact call, task, request, input artifact and key, ordered
attempt membership, and outcome/response consistency. Observation matching
rejects missing, duplicate, extra and reordered references. The generic
source-only Invocation issuer rejects this dedicated field; the model issuer
requires exact slot matching, the INFER profile, the exact Invocation Template
and the call's Program definition. The source-only issuer also rejects an
INFER template when the dedicated array is absent.

Successful saved-bundle records are matched to the successful subset of all
slot captures. Missing or additional records, duplicate expected calls, wrong
input/task/request/slot bindings, and mismatched response/output identities
are rejected. Failed slots do not fabricate entries in the success bundle.
This compares structural references; actual response content is still
validated by the existing bounded restoring owner.

This is structural evidence admission, not an executable capture owner.
Symbolic accounting, authority, policy and outcome roots in independent wire
vectors do not prove execution or custody. The installing owner must verify
those referenced records and supply the complete checked call inventory
before publication. The executable capture-owner and public Host connection
remain unfinished. No adoption-ready public Host SHA is available for B yet.

The schema pins, normative imports and independent vectors move together.
Removing only the optional field reproduces the preceding Run Receipt and
Captured Run schema pins. The touched publication suite passes 188/188 and
canonical JSON passes 460/460 on each of JS, Wasm and native. Node schema and
independent-vector tests pass 3/3; existing publication-contract tests pass
10/10, and protocol-generator tests pass 6/6. The specification gate completed
successfully after updating the two changed embedded-schema pins. The final
structural owner guards were additionally checked with the targeted suites
and canonical gate. These are local checks, not Linux CI or Named Result
acceptance.

### Execution-owned call inventory

Request preparation now retains the exact formal call body generated before
dispatch. An opaque accepted capture exposes its call count and indexed call
in canonical typed-key order, rather than deriving an inventory from a caller
list or the successful-response bundle. Acquiring the capture checks that the
prepared rows, requests, captures, observations and responses have matching
cardinality. Released reads cannot supply this inventory; an independently
retained read keeps its execution owner alive until release and cleanup.

Binding a saved successful slot now checks its actual execution-owned call
and checked response/output observation. Freshly sealed mutations reject with
the exact typed reference error, not merely an unrelated parsing failure.
Restored component replay derives the same call without dispatch. Tests also
cover reverse-authored keys, zero keys, invalid indices and independent reads.
The Node bridge exposes the same opaque reads to the installed capture owner.

Local verification passes on JS, Wasm and native: `client_infer_host` 27/27,
`model_execution` 2/2 and `run_publication` 188/188. The release Node bridge
build and its 35/35 component tests pass, including dispatch-supervisor custody,
real macrotask cancellation and encrypted Store reopen/replay. Interfaces are
generated from the integrated source; formatting and whitespace checks pass.

This unit does not issue external attempt, accounting, authority or policy
evidence. Its binding fixtures use symbolic external roots only. The current
execution capture accepts successful barriers; failure-outcome adoption and
durable all-slot capture remain unconnected. Public Host registration and
committed Named Result retrieval also remain unfinished. These local checks
do not constitute B's public acceptance SHA, Linux CI or permission to push.

## Execution-owned provider outcomes

The model owner now keeps an adopted slot inventory separate from successful
response records. Each success points to its checked response and invocation
evidence; each classified no-response failure retains its actual provider
classification. Ordinary `outcomes` mode emits one keyed row per adopted slot,
with a NULL value on failure. Seven classified failures are covered. Provider
cancellation and cancellation delivered during a callback stop the barrier
instead of fabricating a provider-failure row. Strict mode rejects output at
the first failed slot; prepared but unattempted keys are not adopted outcomes.

Successful capture bundle shape and identity remain unchanged. Such a bundle
contains only the successful response subset and is not the full slot list.
Live opaque replay prepares the ordinary input and verifies every call/key
again, then reuses successes and failures in canonical key order without a
provider. Invocation-evidence lookup uses the logical slot position rather
than a success-subset index. Stored success-only replay still rejects an
incomplete key inventory; durable replay of failures remains unfinished.

Private `ModelOutcomeRead` custody can retain an adopted prefix after strict
failure, including preceding successful evidence. Physical stop is required
before acquiring it. This read is not accepted-output authority or a completed
ObservationSet. Independent reads keep the original input and observations
alive through failed cleanup; releasing the last read permits cleanup without
another model call. Released reads and unattempted slot positions are rejected.

The existing physical ledger gains `mark_transfer_uncertain`. A dispatched
call with no confirmed wire observation moves its reserved upper bound to
uncertain transfer usage. Cleanup releases physical retention/execution but
does not refund this unknown usage. This is not an exact measured charge and
does not establish the still-missing token, cost or duration accounting. The
primitive is shared; no model-specific ledger or Run state machine is added.

Independent one-row bounds cover ten model work transitions and 66,536 bytes
of request/response retention. Exact limits admit the failed outcome; one-short
rejects with `WorkLimit` or `Ledger(RetentionLimit)` before the callback. Other
tests cover all-failure rows, mixed replay, exact typed capture mismatches,
no-response artifacts, cancellation races and strict-prefix custody. Local
JS/Wasm/native suites pass: inference owner 34/34, model owner 2/2, publication
188/188 and physical resources 16/16 on each target. Node bridge integration
passes 36/36, dispatch-owner regressions 13/13, and contribution generation,
formatting and whitespace checks pass. Generated interfaces are refreshed.

The Node Option-returning legacy provider still represents an absent decoded
response as `ProviderError`; it is not a full raw-response classifier. These
tests do not claim actual error-response issuer evidence, retry/backoff/media
admission, formal adoption/accounting/authority records, durable all-slot
capture, installed public startup or committed Named Result retrieval. No
push or Linux CI success is claimed, and no adoption SHA is supplied to B.
