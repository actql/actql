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

- Derive and admit the barrier's fixed request, input Artifact, call slots,
  classification and execution envelope from the same prepared Program.
- Extend `run_publication_host` task compilation to represent the acquisition
  boundary without passing INFER through pure AoA lowering.
- Connect that compilation and the model execution to the existing
  `client-dispatch-owner` and publication owner, retaining stop and cleanup
  custody. `local-values-plan.mjs` currently supplies empty model evidence.
- Read the committed Named Result and compare it with the independent row
  expectation before supplying an adoption SHA or Host startup example to B.

## Checked compilation prefix

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
