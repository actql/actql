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

The Core operation-explanation read accepts the original prepared Program and
its nominal Values or task compilation. Equal re-preparation, copied JSON and
a matching CID cannot replace that owner. Its occurrence DATA retains the
original compiled Plan, Program Definition, effective Parameters and logical
Stage/operation coordinates, including input-only occurrences.

Meaning is read from the checked operation: VALUES schema and authored row
cardinality, FILTER's typed predicate, ordered SELECT/RENAME/DROP projection,
and JOIN's kind and left/right keys. Those are borrowed immutable compiler
facts, not another interpreter or runtime snapshot. An operation lacking this
explanation projection remains `NotProjected`; it is not a language refusal
or an empty/successful computation. Authored VALUES cardinality is not a count
of acquired, processed or written rows.

These internal Core values cannot be sent as private handles. The separate
closed structural Explanation Facts family emits shape/nullability, ordered
projection, JOIN keys and a finite checked predicate projection. It omits
literal values, inferred bounds, literal collection sizes and value CIDs.
An unsupported predicate form remains explicitly unprojected as a whole.
Public emission still needs the selected existing-Owner disclosure/current/
egress checks and finite construction/output admission.
In particular a typed predicate is not unconditional permission to disclose
its literals, a Task prompt or a Source body. Registering or reading these
facts installs no Sample, execution boundary or durable control.

The structural envelope borrows the same compiled owner and original logical
map. It copies that map's Step keys and input/output port identities; it does
not issue them again. Capture follows the existing static-plan construction
admission. A separate measuring writer then quotes the exact body and complete
self-identified output without rendering another wire. Those extents are DATA,
not physical backing: the caller still funds the measurement, original map,
emission, canonical parsing and hashing overlap in its existing read scope.
Only the existing canonical identity owner seals the new envelope. Retained
sealed facts support historical reads; the capture constructor is not a repair
path for an old or Normal Run lacking them. This compiler API alone exposes no
Host capability, current read service or Saved retention mechanism.

The shared static Story renderer consumes that same SDK-admitted Plan view.
It preserves original logical occurrence keys and each input/output port;
presentation items issue neither a second graph identity nor execution order.
An input-only occurrence remains input/output, and an unresolved Stage locator
does not establish a Source, Result publication or physical acquisition.
Effect declarations remain outside the computation dependency graph. English
and Japanese text is deterministic presentation of these same facts, without
another SQL parser, LLM call or inference of business meaning from an alias.
Exact/bound/estimate/unknown quantities and unsupported runtime capabilities
remain distinct. Missing typed expression, Task or source-origin facts require
an original-Owner projection, not reconstruction in a renderer.

Saved Story reads use the existing original Run Plan read and its current
authorization. Compiling edited authoring text cannot replace that original.
Locale and presentation labels do not alter Program, executable Plan, Preview
or permission identities. This presentation model is not a new wire contract.

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

## Original logical boundary borrow lifetime

The logical-key wrapper owns an independent borrow of the same original fact,
issued by the existing task owner only after that Run's Ledger reserves the
complete fixed fork, wrapper and bounded lookup constructor peak. A caller
cannot replace that admission with a Boolean, a numerical quote or a different
Ledger. No new logical identity is minted. The source observation stays with
its caller and can be returned independently after the fork is issued. During
admission it is pinned against a reentrant return; the same current fences and
nominal record are checked again before delivery.

Each wrapper has an explicit return. It disposes its heavy original context
before requesting token return, so autonomous Owner retry cannot refund a live
facts/Run/step context. Only the same token remains for declined cleanup, under
the existing Owner retry path. A completed scalar token tombstone makes repeated
logical close idempotent. Failed construction and
unprojected boundaries return only their unused fork. Stopping, losing a plain
wrapper reference or returning another consumer cannot acknowledge that debt.
The fixed lookup holding does not fund capture of the original facts tree,
variable key encoding, a physical parent, Journal ACK or egress; those actual
supplier duties remain separate.

## Original task-owner control gate

The finite Core gate reuses the existing captured task activation and output
commit owner. Explicit pre-work setup installs at most one control state under
that Run's original graph/strategy hook. It does not add a CapturedDAG field or
allocate controller state on the default Normal path. The hook's added control
reference and admission fence are included in its existing construction quote;
the controller separately reserves its complete fixed binding/state/read peak
on the same Ledger before construction. The configured Local owner matches the
actual Account decision to its original Run Definition and execution context.
A task activation grant does not substitute for this control permission.

A step is the existing resume interval ending at one original logical operation.
Its before and settled observations consume one credit only when the existing
owner atomically commits that operation's output. The gate then blocks the next
activation, or observes genuine final task completion. Pause during work waits
for that commit; failure and stop cannot spend the credit as success. Fused
prefixes and unavailable physical boundaries refuse before work rather than
inventing independent logical stops. No task execution or Sample is replayed.

The interactive revision belongs to this single Run-owned state, independently
of strategy generations and the legacy cancellation counter. Commands compare
that revision and actual original authority before mutation, reserve headroom
for an automatic pause/terminal transition before work, and fence resource
callback reentry. Stop disposes the admitted binding before token return;
declined cleanup retains only that same token under the existing owner's retry.
No second holder can reset revision or acknowledge another owner's return.

This Core state is not a durable command receipt or a public controlled Run.
The existing journal still needs its separate marked associated-state and
immutable operation/lookup transaction, original-row CAS/current checks and
first durable acknowledgement before runtime enablement. Existing public
pause/resume, interval and receipt schemas stay closed and unchanged; durable
control and Sample capabilities remain unavailable until their actual supplier.

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

### Original adaptive failure observation

The fixed Node dispatch can project the original `NoStrategy` task and at most
eight already-retained search assessments through the existing Request capture.
It never reruns search, implementation estimation, policy or admission. The
collapsed decision and feasible-candidate count are not retained and remain
explicitly unavailable. Report completeness and bounded truncation are separate.
The same Ledger refusal spelling is used by the existing strategy explanation.

Journal payload acknowledgement drops committed Plan/Facts aliases while the
same capture borrower remains in the existing manager until its original cleanup.
The explanation and logical observer are distinct simultaneous roles: the original
Resource census and pre-constructor quote include both; a ninth unrelated loan is
still refused. Current, holder identity and captured-DAG/Ledger identity surround
projection. One attempted read is latched before callbackful current/growth; a
refused or reentrant observation cannot replace the primary failure or reset debt.
Fixed controls are prepaid and bounded original/Node DATA coexistence is added to
the holder's **current** extent before construction. No new Owner or public read
permission is issued. Old namespaces without this connection retain unavailable
failure details and their existing early capture return.

### Retained structural explanation read

`Execution.explain(options)` uses the Client–Host `run-explanation` command,
parallel to the existing execution `plan` and `inspect` reads. Its only options
are `maxWireBytes`, `maxNodes`, `maxDepth` and `signal`. Aborting the signal cancels
this read, never the Run. `Client.plan` remains a pre-execution read; this cut
adds no `Client.explain` alias.

The closed `WireRunExplanationView` retains the full original `run_ref` and
structural facts, or the existing explicit `not_projected` reason. The Host
checks current Run/Plan read and egress before acquiring retained evidence and
again before disclosure. Missing old/Normal evidence is not a reason to compile,
acquire Source or infer again. Read-budget and encoding failures are named
refusals, never truncated facts or `not_projected` substitutions.

The retained-facts service requires a specific associated-original lookup in
addition to the existing Run lookup. Omitting that connection refuses service
installation; it cannot fabricate old/Normal absence. Both current Run/Plan read
and egress checks surround the retained read. The same original Definition,
program and Facts bytes are checked again after awaited authorization.

The structural read uses its own existing READ Request admission, independently
of the producing Run's retired capacity. Its fixed entry is backed before
Account callbacks or Journal access. A native scalar-only extent probe precedes
the full original-row projection; that projection rechecks every wire/binding
bound inside SQLite. Growth or corrupt text refuses before an oversized String
crosses into the Host. The complete cold codecs and original map/key binding
construction use the same Request, not Result metadata slots or another Ledger.
The selected bounds live in that Request's existing phase slot and cannot be
substituted at the final constructor.

Structural metadata uses the installed Account's exact `run/read` permission,
separately from connection/current checks and from each named Result permission.
One owned read operation carries the before/after Account memo; an application
callback reobserves changed Account/current facts without reusing an outcome
across public reads or across resources. Identity equality is not an Allow.
The actual transport must keep the read backing through output consumption and
dispose its original semantic aliases before refunding it. Pending physical
output/cleanup is not an acknowledgement. Read construction or Source checks
alone do not enable an installed public capability.

The private HTTP ingress consumes the view under that same read: its native
end callback confirms output consumption, and an output error retains backing
until the response actually closes. InProcess instead completes an independent
caller-value copy before returning the Host read. Both paths pre-admit the
parsed-value, escape expansion and output-buffer overlap; neither returns a
Host-owned parsed alias or treats starting a send as completion. The installed
connection check does not pre-evaluate the Explanation Account gate outside
this admitted read.

### First structural facts admission

New ordinary Runs select finite structural metadata at the existing first
original-Plan admission, without a new public caller flag or Debug switch. Its
meaning comes from that same compiled Plan, logical map and checked owner.
This is static compiler metadata, not execution Samples, history or tracking.
The actual installed constructor must reserve measure/writer/hold/parse/hash
construction on the same Request/Plan capacity before allocation and retain
that backing through the same first durable acknowledgement. A Journal codec
or currentness callback alone supplies no such backing.

The request Journal stores the closed Explanation Facts body as an associated
facet, bound to the full original Run reference, in that existing first
admission transaction. The old Run Definition, Plan and admission-evidence JSON
remain byte-identical. No second Store, network operation or semantic transaction
is added. Exact additive table DDL remains under the existing schema/SQL support
boundary; unknown format or unsupported selected facilities are not guessed.
Insertion and the original Run admission commit or roll back together. Physical
Store/COMMIT uncertainty keeps its original failure and cleanup custody.

Only the original compiler-control selection can supply those first bytes.
Equal caller wires cannot mint it. Found legacy Runs bypass the issuer, and a
later call cannot attach absent facts. Saved reads use the associated immutable
original; absent old/Normal facts remain authorized `not_retained`, with no
compilation, acquisition or inference repair. Corrupt original bindings and
read/encoding failures are named refusals, not missing-evidence success.
The explicit cold-facet query compares original-reference scalars inside
SQLite and conditionally returns the complete Facts bytes only within the
selected byte bound. Corrupt oversized rows never cross into JavaScript as
full or truncated evidence; row absence remains distinct. Native file and
statement construction still requires its existing physical-owner backing.

If the optional projection is unsupported or its own quote refuses before
construction/IO, the ordinary Run may retain its old Plan without Facts. This
cannot hide cancellation, stale/current loss, primary errors or unknown physical
Store/ACK outcomes. The initial capture supplier and actual read/egress backing
remain separate implementation duties. Capability advertisement waits for that
supplier and uses only an existing extensible discovery surface, never an extra
field in an old closed capability or Run/Plan body.

The optional quote is selected while the original Request capacity is still
working, after its one compiler artifact exists and before module completion.
Structural geometry reads that artifact without issuing a speculative Run,
authorization or Definition. A known optional quote refusal first disposes the
measurement frame, then reconciles the same original working debit under
currentness; it does not leave a partial metadata charge on the old Plan path.
Current loss and cleanup failure remain failures. A successful typed loan keeps
the complete projection peak, adopts only through that same Request owner,
and moves its original borrower once into the capture continuation. Later
module/adoption costs remain charged alongside it, rather than being reused
as metadata funding. Explicit return retains only original cleanup identity.

The installed first-capture continuation verifies the adopted Run's original
preparation, retained compiler artifact and Definition before selecting that
same preparation's body holder. It reserves quotation controls, bounded IR
measurement and complete Plan/Facts construction before their constructors.
The portable recipes are shared with the existing Native static-Plan reader;
Native raw allocation endpoints stay with that adapter. The retained parsed
view/map, old Plan wire, identity-free Facts body and sealed Facts overlap are
separate costs. Measurement never supplies its own funding or another Ledger.

The same Run's existing synchronous preparation-writer fence covers both
capture and sibling-borrow current callbacks. Normal retains the same fields,
and static-only projection selects no additional capture holder or output
tuple. Borrowed first-admission wires reobserve original currentness before
exposing semantic aliases; a stale failure is typed, never missing evidence.
Explicit return cuts compiler/map/wire references before lower cleanup can
settle, retaining only the original token responsibility on a pending return.
That return is not a Journal or physical-stop acknowledgement. The actual
Journal adapter must retain this loan through its first durable ACK or unknown
commit reconciliation; a Core component alone cannot advertise the read.
