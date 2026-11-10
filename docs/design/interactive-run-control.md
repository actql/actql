# Negotiated Interactive Run Control boundaries

The initial negotiated wire registry lives in
[`actql-interactive-run-control.json`](../../spec/contracts/actql-interactive-run-control.json).
Its closed shapes and identity domains are separate from the unchanged closed
`actql-run-state/0.1`, legacy start intent, and Run Definition. Registration
does not install a scheduler feature or confer execution authority.

## Read-only current Run projection

The initial Node Inspect service reads the original retained Run Definition and
prepared/authorization evidence through the existing request journal. Current
authorization is checked before acquisition and again before disclosure. The
portable publication projection verifies original Plan, template, execution
context, policy and Run-reference bindings, and verifies the existing Owner
snapshot CID. Inspect neither recompiles the Program nor advances Run control.

The resulting view is explicitly non-atomic and Owner-local. It retains the
unchanged legacy Run state and its observed control revision. Missing pending
flags remain omitted/unknown; unsupported pause, Sample and cost capabilities
are separate facts. No logical map is reconstructed from physical tasks.

Run status and cancellation metadata do not consume the saved logical map.
The request journal retains its bounded original strings alongside the
admitted Run and current control flags without re-admitting that unused map.
The compiler's nominal initial selection already checks its Plan, Program and
Run binding before acceptance; the journal still checks the original ticket,
shape, limits and exact duplicate bytes. The actual authorized stored-plan
reader admits and checks the map when returning it. This preserves semantic
verification at use without repeating it at every unrelated metadata lookup,
and adds no permission cache, replacement map or revision.

A Local status observation retains its journal's nominal admitted Run frame
through Store observation. Its existing control probe can start from that same
frame, selected namespace/scope/Run key and original control instances. Each
probe still reads the complete current row; exact scalar equality reuses only
the admitted revision/cancellation facts. A changed row is admitted again,
including payload changes without a revision increment. Copied or foreign
frames cannot seed the probe. Missing rows and failed reads clear its retained
facts, and closed journals refuse. These managed references end with the
observation; they retain no current Account decision or physical cleanup ACK.

The final state publisher still compares the complete original row after
projection and performs the existing transactional CAS for a changed state.
Control changes and publication conflicts retry with a fresh admitted frame.
An internal post-Store probe therefore does not repeat admission of identical
Run bytes, while a new public observation acquires its own current original.

Within one Local wait invocation, the next poll may borrow the last completed
observation's bounded, nominal Journal frame through private caller arguments.
The Journal still checks its original controls and lifetime, reads current SQL,
and compares every field before reusing the admitted DATA. A changed row takes
full admission, even without a revision change. First/cold observations and a
distinct wait start without this borrow. Store authorization, cancellation,
the final physical/current fence, state CAS, readiness, wakeups and unfinished
read/cleanup duties remain unchanged. No frame is copied, persisted or shared
between wait invocations, and no Account decision or ACK is retained.

The ordinary Local observer selects committed publication through the existing
authorized state service, not a preliminary Index probe followed by the same
probe inside that service. The Store can return its selected entry together
with the nominal Index admitted from that same physical read. State projection
consumes that original rather than rereading and readmitting the identical body.
These immutable metadata facts live within this observation; a new operation
acquires its own bytes, digest/link checks and original close duties. They are
not Account decisions, payload availability, a durable ACK or a cross-operation
successful-read cache. Result retention and physical payload checks remain
separate selected duties.

Authorized absence selects the existing unpublished branch. Denial, malformed
selected originals and physical failures do not become absence or trigger a
fallback read. The strict committed-state entry still refuses a missing Index.
Stores without the optional combined read keep their original selected reads;
an explicitly invalid combined port refuses. Final Journal row comparison,
current authorization and transactional observation CAS remain unchanged.

Within one authorized Run observation, each distinct Result clock contract
accepts one durable floor through the existing Store clock sampler. Sampling
occurs inside that owner after its original durable-bound read, not before
queued I/O. Later Results sharing that contract reuse the accepted floor and
check their own observation time for rollback and retention expiry without
another durable clock update. Their observation timestamps do not claim a
new persisted floor. Distinct clock contracts and new public operations retain
independent sampling. A failed sampling outcome remains Unknown for that
contract throughout this observation; another Result does not retry the
mutating operation. The private clock facts never enter authority callbacks.
Stores with only the explicit-observation API retain that protocol; an invalid
sampler or missing comparison predicate refuses service installation. Current
authorization, final state comparison/CAS and real payload/FD cleanup remain
unchanged.

Physical-stop observation uses the same journal-owned frame across publication
inspection. An unchanged complete row reuses its original request identity and
Run Definition admission; revision equality alone is insufficient. The final
physical-close transaction compares that complete original row before its
guarded update. A changed row refuses the stale stop observation, while a real
COMMIT failure retains the existing Unknown outcome. Copied, foreign-journal,
foreign-control and wrong-key frames refuse. Cleanup and physical-stop receipts
remain separate prerequisites, and an already recorded stop needs no repeated
publication inspection. These facts live only within the existing operation;
they do not cache Account decisions, issue a cleanup ACK or replay execution.

A public Run-state observation may update only its observation key/counter while
the physical-stop owner awaits publication inspection. The same Journal can
compare two of its admitted frames and recognize that narrow metadata-only
change; every other selected column, control, key and admission receiver must
remain exact. The first observation retains Common's zero counter. Only this
comparison permits one immediate full reinspection through the original
Journal, Store and Common decision. It never relaxes the final complete-row
transaction check. Changed immutable/control facts, missing or foreign frames,
and another overlapping change retain the original physical owner's pending
observation; they issue no stop acknowledgement or terminal outcome.

This limited profile refuses Inspect when an older record lacks original policy
evidence, or when a resuming state lacks the required continuation/fence origin
observation. The underlying original Run and legacy status API remain usable.
Missing evidence never authorizes reconstruction from current configuration,
new execution or a fabricated revision/origin. New source-free Values admissions
retain their existing prepared/authorization evidence in the journal's existing
bounded evidence field without changing Run identity or execution meaning.

The installed Node read profile reports both static planning and Inspect as
Host support facts on either view. The Node consumer explicitly supplies that
installation fact to the portable issuers; a common compiler or shape parser
does not infer another Host's support. Unsupported control, Sample, full
intermediate retention, cost and batch capabilities remain false or empty.
Static observation and current Run provenance stay separate from those support
facts. Capability flags and operation hints are not authorization tokens and
do not replace current access checks or update the original policy identity.

## Existing-Owner connection inventory

| Boundary | Existing authority or fact | Negotiated connection |
| --- | --- | --- |
| Original request | Submission epoch/reference and request journal | Normalized requested Profile and optional expected Plan in original intent; duplicates restore that same intent. |
| Original preparation | Checked logical IR and admitted Compiled Plan | External immutable map, deterministic Step/port keys, then resolved Profile/admission. Plan preimages are unchanged. |
| Run state | Common Run/control revision and claim/fence | Separate negotiated projection; no second lifecycle, clock, or terminal decision. |
| Formal resumption | Checkpoint/Resolution Owner | Genuine original evidence, distinct from a manual command origin. |
| Operation lookup | Original accepted operation and journal | Immutable initial receipt plus separately linked later outcome; absence is not resend permission. |
| Inspect | Existing currently authorized Owner-local observations | Explicit non-atomic composition and provenance; no global synchronized snapshot claim. |
| Stored output | Existing material/publication/Store custody | Actual producer output or receiving input locator, not a synthetic produced Step. |
| Local storage binding | `client_local_run.issue_local_result_durable_binding` | Existing original nominal Run/invocation/retention with current account validation and observed physical bytes; no Sample, commit, or Run outcome is inferred. |
| Retention | Existing resource claims and cleanup | Separate Sample, full-intermediate, and continuation lifetimes; registering a Sample shape allocates none. |
| Cost | Existing checked Ledger quantities and selected tariff/scope | New finite amount syntax only; no new price, currency Catalog, budget, or charging Owner. |

The portable `run_publication` package admits canonical shapes and their
registered self-CIDs with the existing parser, schema-validation cursor and
canonical sealer. Its cross-record checks detect Plan/map/profile/request/Run
substitution. These checks do not prove that a map was compiler-issued or that
referenced Sample values were originally admitted under their Carrier/type
contracts: those facts remain with the named Owners. An adapter cannot acquire
authority by sealing an arbitrary sidecar.

Logical Step keys bind the original Plan, checked Stage ordinal and actual
semantic occurrence. Input-only Relation output uses `input_output`; it has
exactly one actual input and output of the same Relation contract. Ordinary
operation keys retain their checked operation ordinal and typed compiler tag.
Port keys bind Plan, Step, role and ordinal. A receiving input retains its
original producer/source locator. IDs are never physical task numbers or
runtime dispatch order.

## Legacy consumer truthfulness

### Typed current-state wait projection

The existing `run_publication` Owner provides a closed `RunWaitUntil` choice.
`Stable` preserves the original wait readiness, including a waiting Checkpoint
or reconciliation; `Final` follows those phases until the existing Run outcome
is succeeded, failed or cancelled. Both consume the same bounded, validated
Run-state record and require an observation strictly newer than `since` when
it is present. The original default entry point and wire are unchanged.

This read-only projection does not create a transition, infer missing Run data,
answer an approval, grant dispatch, or acknowledge physical cleanup. A final
semantic outcome can retain unavailable Results or unknown physical-stop facts.
Native status following consumes this Owner decision instead of maintaining a
second adapter status table; its clock/deadline and current lookup remain Host
responsibilities.

The old SDK continues to expose only its original RunState. A negotiated
paused state, or manual-origin resuming state, refuses old projection with
`RunStateVersionUnsupported`. Where an exact legacy projection exists, Run,
status, timestamp and the original integer control revision must agree.
Formal-origin resuming does not invent approval: real Resolution, continuation
generation and fence evidence still require their existing Owner validation.

The generated client-wire additions are types and shape validators, not
pause/resume methods. Installed capability publication must distinguish static
Plan reading, authorized Inspect, durable control, each Carrier's Sample
capture, full intermediates, Cost Guards and execution batches. A missing
runtime is not made available by recognizing its schema.

The negotiated pending flags are optional observations. Only their existing
Owner can supply a boolean; omission remains unknown and is never defaulted
to false. A Host's unsupported pause or sampling capability does not prove
that cleanup is complete or that an unobserved responsibility is absent.

## Exact amounts and independent projections

Negotiated `amount_micro` is a decimal string in the nonnegative signed-Int64
domain, matching existing checked Ledger `cost_units` aggregation. Values
above JavaScript's safe integer range retain exact digits. Decimal-unit facade
normalization is distinct and never uses binary floating-point arithmetic.
This finite protocol domain is not a language-wide mathematical Money limit.
Currency syntax alone does not establish ISO support, a tariff, or a price.

Relation presence is independent of NULL. Graph Samples retain original typed
definition/domain/key/edge identity without inferring complete topology.
Vectors preserve original dimensions, precision and component positions;
Events preserve occurrence identity and only available order/clock evidence.
These are bounded projections, not full snapshots, continuations or formal
Results. `forbidden` carries no source, count, shape or references; ambiguous
input selection is `selection_required`, not a silently chosen port.

Read-only PlanView/Inspect may be connected independently. Durable execution
control, Sample capture, Cost Guards and other Host/runtime profiles require
separate original-Owner implementations and acceptance; they are not implied
by these contract definitions.

## Static compiler projection

The Node read service prepares through the installed ordinary checker, then
uses the existing Values or task compilation issuer. The shared MoonBit
projection requires that compilation's exact original prepared owner and reads
the checked Stage IR, including fused logical operations and input-only
Relation Stages. It accepts no caller-authored map as compiler provenance.

The `plan` request carries the authored input, supplied parameters and finite
wire/node/depth limits, but no submission or Run identity. Its static service
does not depend on the request journal, Source acquisition or execution driver.
Current connection access is checked before preparation and again before
returning the view. Unsupported compilation profiles refuse rather than
running a probe or issuing an executable Run. Unknown work remains unknown;
stop, Sample, intermediate retention, cost and batch capabilities remain
uninstalled. The SDK checks the returned map's self-CID and Plan binding; this
read grants no execution authority and does not install runtime control.

## Effectful static planning

The separate `actql-effectful-static-plan-view/0.1` envelope implements the
adopted X02 readonly connection. The original Effect preparation/compilation
Owner supplies both the existing computation PlanView and a freshly read
checked declaration set. Neither a copied mutable snapshot nor its CIDs can
issue a replacement original. This preserves all existing PlanView/map bytes
and makes no new execution, approval or recovery decision.

The nested DAG is explicitly a computation component. Declared Mapping target
references and Command Resource kinds remain authoring facts. Contract minimum
none/required/not-represented stays separate from current permission, gates and
approval; unknown physical targets/changed values and unavailable sealed Preview
are not replaced with guessed values, synthetic Checkpoints or ordered edges.
The same finite member/work and complete read/emit bounds apply. Host current
readonly authorization and public installed acceptance remain independent
requirements; a Core projection or schema registration alone installs no support.

## Compiler-original plan capture

Initial plan capture consumes the same nominal compiled Run, checked Program
and admitted Run Definition. The portable compiler projection has already
closed the logical map against that Plan and Program under its projection
bounds. The adapter retains those immutable original strings with the existing
wire-size ceilings; it does not immediately run the independent stored-input
reader over its own output. An authorized durable plan read still admits the
selected stored Plan and map and checks their identities before disclosure.
Capture is neither a permission cache nor a replacement for that read boundary.

## Compiled Run definition binding lifetime

The existing compiled Run holder retains one completed Values or task binding.
Reuse requires the exact original checked Program, compilation, template, Plan,
prepared and authorization evidence, admission and nominal Run Definition.
Serialized equality or a matching CID cannot substitute for those tokens. A
restored or changed input runs the original complete binding check before any
new facts are retained. A failed check preserves the last successful binding;
a different successful Definition replaces that single slot. The slot retains
the typed binding and original references without decoded wire copies or a
reference back to the compiled holder.

This is immutable compilation and definition data. It does not retain current
permission, a clock observation, Preview approval, request or attempt state,
Index admission, physical resource availability or a commit decision. The
existing Effect binding path remains complete. Invocation emission and static
Plan projection still apply their own limits, and stored Plan/map reads keep
their independent admission. Releasing the compiled holder releases its retained
binding references without issuing a physical acknowledgement.

## Confirmed cancellation DATA

`issue_confirmed_cancelled_unpublished_run_state_wire` encodes an already
established cancelled outcome with `NoAction` and an unavailable,
`not_published` observation for each declared Result. It uses the same bounded
canonical encoder and closed `actql-run-state/0.1` shape as the existing
unpublished computation projections. Result names are checked and ordered;
the supplied inventory is not mutated. No active Checkpoint is emitted.

The original Host owner must independently establish complete cancellation,
absence of publication, current original Run/Checkpoint and approval lineage,
and its guarded durable transition. This DATA writer inspects none of those
origins and provides no evidence for them. In particular, a task stop, absent
response or request acceptance cannot select this entry as a terminal decision.
An approved or uncertain Effect remains subject to its existing pending and
reconciliation duties. The writer neither removes historical Checkpoint
artifacts nor acknowledges physical cleanup. Existing pre-Checkpoint and
Effect-free writers retain their original physical-fact validation.
