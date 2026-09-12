# Integrated pipeline checking context

`pipeline_check_context.check` constructs an opaque `PipelineContext` by running
the existing order, binding and capacity integration boundaries together. It is
a main-side building block for the
[pre-lowering Program boundary](pure-operation-checking.md#main-and-lowering-ownership),
not that completed boundary and not a Check Environment artifact or CID.

The target orchestration and sealing conditions are defined in
[Checked Program construction](checked-program.md). The components below feed
that single validating entrance; callers do not assemble the formal result by
choosing an arbitrary subset of these helpers.

## Construction and ownership

`check_resolved_orders` accepts an already validated opaque CheckedOrders when
publication ports have to be prepared before checking a consumer stage. It derives
the CheckedResults and producer closure from that object; neither is a second
caller argument. Guard binding and capacity validation consume exactly that
closure, and the resulting context retains the same order owner as the ports.
The ordinary `check` entry resolves orders first and delegates to this same path.
Thus reuse does not bypass binding, expression inventory or capacity checks.

The reuse entry's work/text limits include the order result's prior usage and
reject negative or insufficient caps before subsequent work. Step/Result/depth
admission bounds were applied by the earlier order/Result constructors and are
not retroactively replaced by this integration entry. Prepared ports are still
not an execution authorization, including when later context checking fails.

The constructor starts with `relation_results.CheckedResults`; its retained
pipeline determines the root. It resolves all contextual producer orders and
root publication orders, collects outstanding static expression requirements,
binds guard quantities for every producer occurrence,
then validates all supplied local capacity coverage and proof/input ownership.
The latter two phases receive the exact contextual closure constructed by the
first phase. The caller cannot substitute a separately resolved closure or pair
order decisions with a foreign bound-guard collection.

Bindings and capacity entries use contextual producer occurrence order, root
first. Repeated producers and unused branches remain separate visits. Their
declaration owners, selected policy and capacity dependency registrations are
validated by the existing closure checkers. Equal names, values or types do not
substitute another declaration, pipeline, source collection or producer. Prior
source/type admission and local capacity evidence construction remain explicit
prerequisites, not unchecked JSON or `validated` flags.

The result retains checked Results, resolved orders, static expression requirements, bound guards and capacity
closure through read-only accessors. The constructor does not retain caller
arrays. Errors preserve the originating order/binding/capacity diagnosis,
including the failing producer. A late failure exposes no partial context.

## Cumulative limits

Step and Result caps are passed to whole-closure order resolution. Work and
text budgets are shared: order resolution consumes first, expression requirement
collection uses the remaining work, guard binding receives the remainder, and
capacity closure receives the remaining work. Successful
usage is exactly the sum of those phase usages. Capacity closure includes the
retained local coverage costs under its existing contract. This is an
integration-work budget, not the cost of earlier parsing, type checking or
constructing local capacity evidence, and not a heap or execution limit.

Tests cover repeated/unused producers, exact shared closure handles, detached
caller arrays, summed usage and exact/short budgets. Negative cases include
unresolved publication order, missing/foreign capacity entries, invalid caps,
binding-count mismatch and a late equal-content foreign declaration owner.
Existing allowed publication fallbacks remain allowed; a missing candidate key
alone does not require failure when the selected Result projection supplies an
admitted ordering strategy.

## Outstanding static expression requirements

Every producer visit is scanned using the exhaustive local expression-slot
collector, including unused steps and repeated visits. Each pending profile,
pattern or Host envelope requirement retains its visit, step, exact typed
expression and annotation-node index. It remains a **static** requirement,
not a runtime value check, a discharged fact or permission to execute. Requirements
inside unselected expression branches are retained. Equal kinds or profile names
at different occurrences are not deduplicated.

Collection charges one unit per visit, local slot-collection work, one per
retained expression and one per pending requirement. Indexed access to the
expression's pending requirements avoids copying its whole array before checking
the budget. `expression_requirement_work` reports this phase's contribution;
count/index accessors expose the immutable inventory without its backing array.
Tests retain both NFKC and an unselected regex branch through repeated producer
visits, distinguish all three requirement kinds and check exact/short budgets.

This inventory covers expression requirements only. An empty inventory does not
mean every operation-level obligation is discharged. The formal Program checker
must bind validated resolutions to these exact occurrences and reject unresolved
static requirements; lowering must not reinterpret this inventory as work that
may simply be deferred to runtime.

### Environment-bound expression validation sites

`prepare_expression_validation` consumes the selected-capacity context after
staged Result wiring and input/snapshot reconciliation. It reuses every stage's
existing requirement inventory, without reparsing expressions or accepting a
second caller-provided list. An opaque `ExpressionValidationSite` retains its
exact context owner and stage/inventory coordinates. Its requirement supplies
the original typed expression, node index, step and producer visit; its
`ParameterVisit` supplies that same visit's collected references and bound index.
The bound values are those already checked against the staged Program's single
selected binding owner. Equal-content foreign bindings cannot be supplied to
this entry. Site coordinates and physical ownership are process-local, not
semantic Program or Invocation identities.

The constructor admits `text_time_evaluation` from that context's exact Check
Environment, even when no expression uses it. A malformed present component
fails the whole construction; an absent component remains `None`, with no
implicit defaults. Presence does not establish profile admission, validate a
pattern, derive an output envelope or discharge any requirement. All obligation
kinds remain in the inventory, including non-text-time profile obligations.
An empty inventory is not a claim of whole-Program static completion. Later
resolvers must consume these owned sites and return occurrence-bound evidence;
this context is not a lowering-ready or executable Program.

Limits include the prior selected context's work, text and policy-node usage.
Additional work charges one component lookup, the admitted component's nodes,
one visit per stage and one entry per retained requirement; component bytes
and nodes accumulate into the existing budgets. A separate requirement cap
bounds the site index before allocation. Component depth is checked during
admission. This composition accounting does not remeasure prior parsing, bound
total heap usage or establish runtime resource ceilings.

Tests use two source-bound stages and a repeated producer with an unselected
regex branch whose capture argument is a bound Parameter. They check all nine
pending occurrences, exact expression/binding/environment ownership, independent
equal-content contexts, exact/short/negative budgets, missing policy and invalid
unused components. At this preparation boundary, pattern validation and envelope
derivation remain pending.

### Timestamp-pattern resolution

`check_timestamp_patterns` consumes that opaque environment-bound context and
resolves every `PatternValidation` for `parse_timestamp`, `try_timestamp` and
`format_timestamp`. It derives the operation and pattern operand from each
retained typed annotation, not a caller-supplied expression or pattern string.
Literal data is read once. A Parameter is looked up in the exact visit's checked
BoundValues, using their canonical name ordering; no declaration default is
reapplied and Parameter-looking string contents are not substituted again.
Resolved null/non-string patterns fail static checking even in an unselected
branch. The selected text-time policy is required for every such occurrence,
and its `max_pattern_bytes` applies before pattern construction.

Parse and try use parse mode; format uses format mode. The
[timestamp pattern parser](timestamp-pattern.md) supplies the immutable AST and
CID. Each opaque resolution retains the exact validation site, selected policy
component and selected BoundParameter when applicable. Equal AST CIDs do not
make sites or bindings interchangeable. Repeated producer occurrences remain
separate resolutions, with no caller-controlled evidence list to omit a failure.
Any late failure returns no partially checked collection.
Pattern/policy/value errors identify the original inventory index, so callers
can recover the owned expression's source location and producer visit. A parser
offset refers to the resolved pattern text, not fabricated source-file bytes
inside a Parameter's spelling.

Work/text limits include the prior context's usage, then inventory visits,
constant-shape operand reads, bounded binary-search comparisons, pattern text
and generated AST nodes. AST byte/node limits are cumulative across occurrences;
repeated patterns do not reset them. Successful pattern text is ASCII, so its
length is the exact Host pattern-byte charge. Invalid non-ASCII cannot be
accepted by exploiting the length check. These are integration budgets, not
runtime input/output envelope ceilings or a claim to bound all retained memory.

The collection resolves only these timestamp-pattern obligations. Other kinds
remain in the retained context, including regex/replacement validation, profile
admission and Host envelope derivation. Timestamp value evaluation, calendar
validity of runtime inputs, argument/demand envelopes and Program readiness are
not established by an AST. Later static closure can verify the collection's
exact context owner before using its occurrence-bound resolutions.

## Regex patterns and static options

`check_regex_patterns` consumes the same opaque ExpressionValidationContext,
not a caller-supplied pattern list or separately paired bindings. It scans the
entire inventory and resolves `regex_match`, `regex_extract` and `regex_replace`
PatternValidation obligations. Each opaque result retains its exact site, the
selected TextTime policy, the admitted [pattern](regex-pattern.md), the authored
flags (including absence versus empty), and the selected BoundParameter objects
for pattern and capture/replacement when applicable. Equal AST CIDs across
different contexts do not make those contexts interchangeable.

Literal operands come from the checked semantic node. Parameter operands are
looked up by name in that site's already-selected BoundValues; defaults are not
applied again and strings containing `$` are not resolved as another parameter.
Capture zero denotes the whole match. Other capture indices must be finite
nonnegative integers no greater than the admitted capture count; conversion to
an internal index happens only after that bound check. Nullable declarations do
not permit a null static pattern/capture/replacement value. Replacement parsing
uses the [closed replacement AST](regex-replacement.md), and every referenced
capture must exist. Unmatched existing captures are an evaluation matter, not
grounds to reject the pattern.

The selected `max_pattern_bytes` ceiling counts actual UTF-8 bytes, not UTF-16
units. Replacement text is bounded by the integration text budget, not by an
invented pattern-byte limit. Output expansion and replacement-count ceilings
remain HostEnvelope work: parsing a replacement does not establish those bounds.
Flags have already passed typing but their closed set is checked again; their
authored order is retained rather than silently canonicalized to another value.

Usage includes the incoming context's work/text plus inventory visits, operand
reads, binary-search comparison lengths, source UTF-16 and UTF-8 scan charges,
flags and generated full AST nodes. Both pattern and replacement AST byte/node
costs accumulate across all occurrences, including repeated producers. Pattern
depth is separately bounded. All caps are checked before adding usage; a late
error returns no partial collection. Diagnostics retain the inventory index,
and parser errors include offsets in the resolved source string. The inventory
site still provides the actual expression's path/span/range and binding owner.

Tests cover overridden invalid defaults, bound object identity, unused branches,
repeated producer occurrences, flags, capture zero and out-of-range indices,
nullable static values, multibyte byte ceilings and exact budget
boundaries. Regex matching and complete profile conformance are not tested or
claimed here. The component-specific collections remain available for focused
checks, but the combined constructor below owns their composition. No public
constructor lets the lowerer substitute an unrelated collection.

## Combined pattern validation

`check_patterns` is the main integration entry for all PatternValidation sites.
It accepts one ExpressionValidationContext and constructs the component checks
itself; it does not accept timestamp, regex or LIKE collections from the caller.
The opaque PatternChecks retains that same context and every resolution in the
original inventory order, including reused producer occurrences. The returned
PatternResolution enum exposes a read-only timestamp, regex or LIKE result, not a
constructor for the owning checked collection.

The constructor first rejects any unhandled PatternValidation operation instead
of silently omitting it. It then checks timestamps and regex/static replacement
options, then LIKE, in that deterministic phase order. An error reports its
component and original inventory index. Result ordering does not claim a different global
first-error order across phases, nor runtime first-failure semantics.

All source/work caps include the retained base context exactly once. Each later
phase receives caps reduced by prior phases' incremental cost, not by the
entire shared context. Timestamp and regex AST bytes and JSON nodes accumulate
without overlap; LIKE retains text instead of constructing an AST. Inventory preflight and ordered
collection each cost one work unit per site. Subtraction before addition keeps
all combined arithmetic within the caller's admitted caps. `max_regex_depth`
limits the recursive regex shape; timestamp components have their fixed flat
shape, with their costs covered by the shared AST node/byte caps. A late failure
returns no checked prefix, even if the other pattern family already succeeded.

Mixed-family tests verify site identity and order, repeated producers, exact
aggregate accounting and one-less rejection in every cumulative dimension.
They also demonstrate that a context with only ProfileAdmission/HostEnvelope
sites returns zero pattern resolutions without pretending those sites were
discharged. Host ceilings are not implementation profile claims: the remaining
profile check must follow the conformance owner, not infer support from policy
presence. PatternChecks is still not a CheckedProgram or an executable Plan.

### LIKE pattern admission

`check_like_patterns` resolves literal or Parameter patterns through the exact
owned typed child and binding visit. The opaque result retains the canonical
source string and selected BoundParameter, not a host regex or a fabricated AST
identity. LIKE requires no TextTime policy. Caller work and UTF-8 text budgets
are cumulative across all sites; each scan is charged before traversal. It
adds no JSON AST bytes/nodes. A final unmatched backslash reports the original
inventory index and a UTF-16 code-unit offset within the resolved pattern.
The scan only establishes escape validity, not match results or execution cost.

The normative clarification in the scalar-expression owner follows Sketch
`87dc7144`'s literal trailing-escape rejection and AoA
`dbab4fe8c1d624d81ed967f90e2abe742163f84f`'s scalar escape semantics. Bound
patterns receive the same validation as literals, even in unused branches.
The explicit non-null static pattern requirement closes the case of a nullable
Parameter bound to null: it cannot supply a pattern for compilation. This does
not reject null value operands. AoA's executor-specific hardcoded length and
wildcard caps are not imported as language limits or text-time policy ceilings.
Matching, backend admission and runtime resource enforcement remain separate.

### Context-bound text extents

`check_text_bounds` consumes the owning PatternChecks, not independently supplied
pattern ASTs, values or policies. It connects the twelve portable
[text-time formulas](text-time-bounds.md) to every HostEnvelope site, retaining
that site's selected TextTime policy, input Parameter and numeric length
Parameter when used. A process-local expression slot ordinal distinguishes
multiple expressions in one step, even when a typed expression object is reused.
It is not a semantic identity. Each producer visit is checked independently.

ExpressionRequirement also retains the slot's explicit consumer and its own
aggregate filter dependency. A filter with no profile or pattern obligations
still survives as an exact typed root; it is not lost by the pending-obligation
inventory. Its slot coordinate belongs to that same stage/producer visit, not
the global requirement array or a Fragment roots array. Aggregate arguments
require that filter to be true before their expression-local demand tests;
consumer rebasing must preserve this outer-to-inner order. Equal filter text is
not permission to borrow a different aggregate's root or evaluation frame.

Each slot also owns an [expression-local demand derivation](expression-typing.md#expression-local-conditional-demand),
shared by its text-bound resolutions and exposed by `text_bound_demands`.
Construction and address-segment bytes are included in the shared work/text
budget. The site's typed node index selects its demand and root-relative
semantic pointer. No separately supplied demand list can be attached. Full
consumer placement is still required before sealing the envelope; root-relative
paths are not global fragment addresses.

`text_bound_demand_tests` composes the aggregate filter's root `IsTrue` test
before the local outer-to-inner tests. It accepts only an owned resolution and
an allocation cap, never an independently supplied predicate. Every returned
test retains its exact typed expression and slot in the site's stage/producer
visit. Filter expressions have no self-filter prefix; their own lazy branches
remain local demands. Analytic aggregate arguments use the same composition.
Equal filter source text does not merge frames. No constant folding or row
evaluation occurs, including for constant false or nullable filters. The cap
includes the prefix, and returned arrays are detached. Slot-to-Fragment-root
rebasing remains a separate canonical placement step, not an index cast.

Within a slot, immutable typed topology is traversed in reverse preorder so a
direct text-time child has its output derivation before its parent is processed.
The parent retains that exact producer and rechecks its extent against input
ceilings. Results are returned in original obligation order, not traversal order.
Selected literal/bound string or timestamp values provide actual extents;
other operands use their checked type. An ordinary intermediate operation whose
checked type has no text bound requires RuntimePreflight. This is an explicit
runtime input obligation, not permission to drop the child operation's own
checks, claim an extent was statically established, or evaluate the expression
during compilation. Generic expression bounds are not fabricated by folding.

Bound length values can tighten substring/utf8_truncate. Dynamic expressions,
null, negative or fractional lengths keep the conservative bound; demanded
evaluation errors remain separate. The original checked node's nullability
widens the derived contract when another argument can be null. Derived bounds
never narrow the expression's existing nullable type.

Work/text budgets include the PatternChecks charge once. Pattern lookup, slot
inventory, node-table allocation/traversal, static binding searches and value
scans are charged before use; all repeated occurrences accumulate. No caller
can splice a foreign result into this collection. A late ceiling failure
returns no successful prefix. RuntimePreflight, profile availability and
Unicode implementation requirements are not discharged here.

This closes the typed-site/binding connection for extent derivation, not the
full HostEnvelope obligation: semantic argument/demand/evidence CIDs and sealed
envelope construction remain required. It is still not a CheckedProgram,
executable Plan, matcher or evaluation engine.

## Not yet a checked Program

`attach_stage_contexts` joins source-bound all-stage operation bindings and
source-bound Result checking with exactly one BoundParameters context per stage
in source order. The operation collection owner and each exact CheckedResults
owner must agree. All retained producer visits that have supplied bindings use
the single complete value-set owner selected for the staged operation collection;
there is no per-stage replacement. Equivalent policy admissions are compared by
their verified CID, while different selected policies reject. The opaque
StageContexts retains these owners and copies only the context registration
array. Reordering or omitting stages, a late foreign binding, or a short total
budget exposes no partially attached result.

Its work budget includes bound-operation collection/binding, Result admission,
all supplied contextual work, one check per stage and one per producer visit.
The operation collection retained by both the binding and Result result is
charged once, after requiring their exact shared owner. Text counts direct
operation text, Result-admission text and contextual text. Per-visit work in
independently checked contexts is not deduplicated by coincidentally equal inputs.
This is composition accounting, not a claim to bound earlier parsing or the heap.

This closes the attachment of stage Result checks, selected bindings and policy;
it does not validate ordinary/receipt input contracts, attach Result-import
wiring, discharge static profiles or build semantic Program identities. In
particular, source correspondence for a pipeline is not proof that its supplied
input Carrier contracts correspond to the Program's input declarations.

`attach_result_wiring` extends StageContexts with the opaque, already validated
all-stage ResultWiring. It requires the same prepared Program source and the
exact CheckedOrders owner retained by each stage's published ports. Consequently
the imported ProducedInputs and root exports refer to the publications whose
order, capacity and binding context was checked; equivalent but independently
reissued publication orders reject. The opaque WiredStages retains both owners.
The existing wiring validator remains responsible for exact import producers,
source-order stage coverage and root export resolution, without redoing those
decisions in this attachment.

Its work/text usage adds wiring costs to stage-context costs, subtracting only
the exact shared prior CheckedOrders usage already included by prepared ports.
One ownership check per stage is added. Independent producer-context work is
still counted, not deduplicated merely because the underlying pipeline agrees.
Subtraction and remaining-cap checks avoid aggregate overflow. Negative caps,
foreign source/order owners and short cumulative budgets reject atomically.
The two-stage import test also checks the root export, exact/short budgets and
detached caller arrays. This closes Result wiring attachment, not ordinary or
receipt input admission, static obligation discharge, semantic Program identity
or execution permission.

`attach_local_inputs` extends WiredStages with one source-only local-input
attachment for every stage, including a stage containing only imports. Each
attachment must retain the exact CollectedStage from the all-stage operation
collection, not a newly collected equivalent pipeline. This connects actual
local declaration owners with the already checked pipelines, bindings, policy
and Result wiring. The opaque InputContexts retains detached stage registrations.

Work includes WiredStages, local preparation and local attachment, plus one
registration check per stage. Only the exact shared stage collection work is
subtracted. Local declaration source text is added to the existing text usage;
`max_local_input_nodes` separately bounds the aggregate local declaration nodes,
not all earlier Program parsing or operation nodes. Exact/short bounds, missing
or reordered stages, foreign later stages and same-source recollection are
tested through an actual two-stage Result import. No partial result is returned.

This attachment covers the source-only local Relation path. It does not certify
Host snapshot authority or reconcile richer Host contracts, admit receipt inputs,
close duplicate normalization's total-order requirement, discharge static
expression obligations or construct Program semantic identity. It must not be
used as the final lowering-ready CheckedProgram.

`attach_environment` connects `InputContexts` to the all-stage local snapshot
coverage result. It requires the same Program source and the exact prepared
local-input owner at every stage. Re-preparing equal source declarations is not
a substitute. The opaque `EnvironmentContext` retains both branches, preserving
snapshot environment membership through the Program context rather than reducing
it to a CID or independently supplied schema.

Usage includes both branches and one owner comparison per stage. Only the exact
shared local preparation costs (work, nodes and text) are subtracted once;
snapshot parsing/size, selector resolution and type comparisons remain charged.
Here `max_local_input_nodes` includes snapshot reconciliation nodes in addition
to local declaration nodes. It is still not total process heap or runtime rows.
Tests cover actual two-stage Result wiring, a supplied local snapshot, exact/short
budgets, foreign Program sources and separately prepared equal declarations.

This connection neither retypes the pipeline using stronger snapshot information
nor admits policy, Catalog closure, Host authority or runtime materialization.
Those checks and augmented input registration remain prerequisites of the final
lowering-ready compiler boundary. Snapshot coverage is not execution permission.

`attach_reconciled_inputs` is the schema-aware counterpart to the source-only
attachment path. Pipelines are checked using `environment_input_at`, then their
exact registrations are sealed by `attach_reconciled`. The all-stage connection
requires each attachment's exact operation collection and the matching stage
owner in the Program snapshot-coverage result. It cannot combine equivalent but
independently reconciled evidence. `ReconciledContexts` retains Result wiring,
bindings, policy selection, snapshot coverage and detached input attachments.

Its optional `sourceviews` input joins `sourceview_resolution.PipelineInputs`
to that same boundary, rather than creating a separate Program assembly path.
The resolved Program and wire Check Environment owners must match the local
snapshot and stage branches exactly. Each local declaration partition must use
the same SourceView input collection. A partition cannot silently omit its
remote registration proof. The constructor itself attaches the selected remote
Carriers to every exact collected stage, including unused inputs; callers cannot
substitute arrays of assertions. Re-read equal environments, different source
collections and same-shaped replacement Carrier registrations are rejected.
The retained `reconciled_sourceviews` and `reconciled_sourceview_stage` accessors
expose those checked owners to downstream policy and Program assembly.

SourceView preparation is charged once at this join. Per-stage attachment work
subtracts only that exact shared preparation and operation collection, which
are already charged by the retained branches. The local partition's existing
conservative source-collection costs are not discounted here. Snapshot node/text
measures are unchanged; Catalog body admission keeps its own prior-pass bounds.
This remains type/ownership linkage: direct versus keyed acquisition, requests,
read modes, classification, authority and runtime obligations are not discharged
by the presence of a Carrier. The same environment owner does not turn an
integrity-checked Catalog into whole-Program execution authorization.

Work includes the wired context, complete snapshot coverage and registration
checks. Each attachment's shared operation collection and environment pass are
subtracted only after both owners match. Snapshot node/text costs remain in the
combined budget. Tests follow a snapshot-registered input through an actual
Result import and check exact/short limits, reordered/missing attachments,
foreign Programs and replacement evidence on a later stage.
This closes schema-aware registration linkage, not Catalog/policy admission,
Host authorization, receipt inputs, static discharge or semantic Program identity.

`bind_capacity_policy` connects a `ReconciledContexts` to the validated capacity
component of its exact Check Environment. It first checks environment ownership,
then compares the component's admitted Policy CID with the policy already selected
by stage/capacity checking. Separately admitted policy objects with the same CID
are compatible: policy content identity is distinct from envelope membership.
The opaque `SelectedPolicyContext` retains both, rejecting foreign environments
even for identical bytes and different policy contents even in the same environment.

The aggregate adds the component's canonical byte/node size and one binding check
to the prior context usage. Policy nodes have their own cap and do not alter the
previously bounded local-input node total. These are logical evidence costs, not
heap accounting or a claim that earlier parsing work is measured instruction by
instruction. No runtime ceiling enforcement, Host authorization or admission of
other profile components follows from policy selection. Full environment closure
and remaining static obligations still prevent treating this as CheckedProgram.

`check_parameter_bindings` extends a context with local Parameter reference
indexes for every contextual producer visit. It uses the exhaustive pipeline
collector for both typed expressions and direct operands, including values
cells. Values come only from the already validated guard-binding closure; there
is no second caller-supplied binding array to mix with it. Each selected-value
index is bound to that exact declaration owner. Missing bindings fail when a
visit has references, including unused steps and repeated producer visits.
An empty use set without bindings retains its collected index and no BoundIndex;
it does not establish completeness of unrelated Program declarations.

The opaque BoundParameters retains the original PipelineContext and detached
visit storage. Local references use each retained pipeline source as pointer
root, not a fabricated staged Program path. The enclosing Program collector
still determines stage/root coordinates and covers inputs, Results and Effects.
No expression evaluation, substitution, static profile discharge or persistent
Program identity is implied by this attachment.

Work/text caps include the context's previous usage. Collection charges each
visit, its local scan/index work and newly admitted direct-operand text; binding
charges the previously defined exact-owner selection work. Pointer storage is
charged against work. Late failure exposes no partial bound result. Tests cover
repeated unused producers with expression and values-cell references, exact
binding/index owners, local paths, missing first/later visit bindings and exact
or short cumulative budgets.

This context integrates the supported order, guard-binding and capacity subset.
`assemble_preparation` joins the source producer/application checks and expression
pattern/extent checks through their exact common `SelectedPolicyContext`.
Expression profile checks must additionally belong to the exact expression
validation context; a separately checked equal Program is not interchangeable.
Separate checks of equal Program bytes or policy CIDs do not authorize mixing
the branches. `ProgramPreparation` is opaque and retains both checked owners;
it does not accept a caller's list of independently attachable site proofs.
Combined work counts common selected-policy preparation once, adds branch-local
work and the join, and checks sums before addition. Text includes expression
preparation plus source-request literal text. Source comparison pairs/value nodes,
local-input nodes, policy nodes and pattern AST bytes/nodes remain separate
accounting dimensions, each with an inclusive cap. None is a whole-heap bound.
The original SourceView and expression results retain all unresolved Host
bindings, operation-level profile demands and runtime obligations. This assembly does not
turn an empty unresolved-binding count into acquisition authority, construct
semantic identity envelopes, or declare a lowering-ready Program.

`check_expression_profiles` checks every retained `ProfileAdmission` occurrence,
including unselected branches and repeated producer visits, against explicit
checker declarations for the complete text-time and VecA profiles. The scope of
this check is expression demands, not the complete module's operation inventory.
These declarations are configuration, not a conformance certificate or a claim
that this package implements the complete modules. They are neither the Host's
discovery `supported_profiles` nor backend execution capabilities. Unsupported
requirements retain their original site index and profile ID and classify as
`ACTQL_E_PROFILE_UNSUPPORTED`, following
[Conformance profiles](../spec/conformance.md#conformance-profiles).
The owned result retains the exact validation context and declared selection;
it does not discharge pattern, Host-envelope or operation-wide profile demands.
Assembly requires this result, counts its incremental scan work once, and
exposes it for consumers without admitting independently attachable site proofs.

`check_operation_profiles` extends that owned preparation across all staged
producer visits, including unused branches. It consumes the exhaustive
`pipeline_typing.operation_profile_count/at` classification without copying
operation bodies or arrays. RelA, SGA, TEA, Calendar and text-rank declarations
are explicit; VecA uses the already retained expression declaration rather
than a second independent flag. Calendar requires both Calendar and TEA.
The result retains its preparation and selection, and its inclusive work cap
counts stage, visit, step and individual profile requirements. Failure retains
stage/visit/step coordinates and the named unsupported profile; no partially
admitted result escapes. Those coordinates are process-local, not identities.

Profile requirements follow the normative operation definitions and
[Conformance profiles](../spec/conformance.md#conformance-profiles), not just
the output Carrier or AoA opcode prefix: text-rank is not RelA-only or VecA,
while a graph-to-row projection still requires SGA. The classification covers
the checked pure operation vocabulary, not acquisition, Effects or a complete
Core claim. It neither certifies declared conformance nor discharges retained
profile artifact, numerical, resource or runtime requirements. Backend execution
capability is still a separate gate.

`bind_program_sources` joins these operation checks with the existing complete
Program declaration-use/Parameter-value checks and the unresolved source Binding
inventory. All three results must share the exact preparation, stage contexts
and request-slot owner. Re-admitting equal source bytes or equal Binding names
does not authorize replacing the declarations used by the request checks.
The existing `ProgramReferences` constructor already checks actual Parameter
values and stage pipelines; its inventory rejects unused Parameter and Binding
declarations across the whole Program, rather than each stage independently.
The combined result retains all owners and counts shared stage/preparation work
once. It is an opaque source-check assembly, not an issuer validator or an
execution permit. Missing concrete Host Bindings remain visible through their
inventory; a zero count does not establish acquisition or publication authority.
Its stage semantics accessor selects the same owned source projection for the
[normative stage envelope](stage-semantics.md), without using internal handles
as persistent identity or admitting a different source inventory.

`identify_program_sources` derives the Program Definition and whole-Program
used Parameter Values identities directly from this assembly. Callers cannot
provide a replacement source projection, Parameter set or claimed CID. The
retained Definition points back to the same declaration-use inventory; selected
Parameter values come from the already owner-checked `ProgramReferences`.
Changing only supplied values leaves source Definition identity unchanged while
changing the Parameter identity when their canonical typed projections differ.
This pair is not itself a new wire envelope or a local Invocation identity.

The same constructor atomically prepares every stage's Definition and local
used Parameter Values and used Parameter declaration CIDs. Each opaque `StageSourceIdentity` retains its owned
definition and exact local bound index; no independent stage or value set can
be supplied. Indexed reads do not copy stage arrays. Empty local selections hash
the explicit empty values envelope. Changing a value used only by another stage
does not change this local value CID. This is still not a Unit Definition or
Invocation: namespace, incoming contracts and observed inputs remain distinct.

The local declaration CID hashes the stage semantics `parameters` map directly,
using the same emitter and source-owned used-name selection. It retains defaults
and constraints but excludes annotations, concrete values, sibling-only names
and reference occurrences. Empty selection hashes `{}`, not the empty typed
values envelope. The direct map is the normative external parameter-contract
projection, not a newly invented artifact wrapper. The reference local-unit
encoder accepts a caller-supplied declarations CID without establishing this
projection; this boundary derives it instead. Binding declarations and the rest
of the local contract closure are not discharged by that CID.

For an extracted stage, `stage_identity_local_body_cid` reuses the full stage
semantics hash as the Unit's local body reference. Hashing only the raw
`local_body` member would omit used Binding declarations, reference enumeration
and the expression-contract pin. Reusing Stage Definition instead would mix in
the separate stage name. The existing semantic envelope supplies the required
local meaning without a new wrapper, rehash, or parent-revision dependency.
The explicit used Parameter declaration CID is derived from that same envelope,
so the two references cannot be independently substituted. Unit namespace,
incoming contracts and remaining interpreted contract closure still need their
own validation; the body reference is not a Unit Definition CID.

One cumulative hash byte/node budget covers stage envelopes, Program semantics,
Program/Stage Definitions, local used declarations and whole/local selected Parameter Values. Stage
semantics hashes already owned by ProgramSemantics are reused, not recomputed.
Depth is bounded per emitted envelope.
Inclusive work counts prior source checks once and adds only the new source
descriptor preparation and one retained identity entry per stage; hash byte/node accounting is separate from work and
neither is a physical-memory limit. Phase-specific failure never exposes a
partially assembled identity set. Read-only accessors preserve the exact source
owner and prepared Definition alongside their computed CIDs and measured usage.

### Incoming local dependencies

`collect_source_contracts` retains the selected SourceView inputs of each stage
from the already reconciled Program context, including declarations without an
operation consumer. Each input exposes its owned Catalog role occurrences;
repeated declarations and repeated references remain separate. The collection
does not scan unrelated Catalog members or copy their reference arrays. Empty
stages remain present, and Result imports are not relabeled as SourceViews.

Work includes the reconciled prefix once, one constructor visit, each stage and
each retained input. Separate Program-wide caps bound input occurrences and the
sum of their reference counts, including repetition. Counts are checked before
retaining an input; failure exposes no partial result. Reference count admission
is not a second traversal or semantic revalidation of the referenced bodies.

`bind_program_source_contracts` connects this inventory to a ProgramSourceIdentity
only through the exact reconciled context already owned by that identity. It
subtracts that common work prefix when combining usage. Matching public CIDs or
equal source text from a separately admitted environment do not suffice. The
result retains both owners with constant-time indexed reads through the inventory.

This is input-associated contract evidence, not the canonical local closure
projection. All declared roles of each selected SourceView remain available;
read-mode dependencies, imports, Mapping/Command/ModelTask, policy, capacity and
numeric-law dependencies still require their applicable semantic selection and
validation. Neither this inventory nor an empty SourceView set establishes a
local contract CID, whole-lock authenticity or acquisition permission.

`collect_program_incoming` derives requirements from the source identity's
already attached Result wiring, not from independently supplied edge arrays or
claimed producer CIDs. Each site retains the consumer StageSourceIdentity.
Success requirements retain accepted/completed and the exact earlier producer;
Result requirements retain the exact producer identity and checked ResultImport,
including its publication schema, ordering owner and produced input. The source
and publication owners are compared, not the allocation identity of a replaceable
StagePorts wrapper. Receipt requirements are explicitly unresolved effect/receipt
associations, never fabricated Result ports.

All source stages are visited. The first stage has no implicit success producer;
later stages preserve the authored/default predecessor law. Success and Result
dependencies on the same producer remain separate, as do repeated imports under
different input names. Source coordinates identify diagnostic sites only. The
namespace accessor returns the typed `(program_id, stage_id)` pair, never a
concatenated string, parent revision CID or source index. Internal traversal is
stage order, then success requirement and source import order; this enumeration
is not a new canonical wire preimage or a deduplication law.

Work includes the retained identity preparation, stage/import index visits and
new requirement entries. UTF-16 name units have a separate cumulative cap,
including names inspected during map construction and lookup. Requirements have
one Program-wide count cap. Index sizes are checked before allocation and a late
failure returns no partial collection. Indexed access does not copy collections.

This boundary is an owned requirement inventory, not a Unit Definition or a
success certificate. The normative local-dependency schema additionally requires
local contract closure, import interfaces and incoming success contracts.
Effect/completion contracts, receipt correlation/freshness and actual successful
execution cannot be substituted by empty maps, matching types or a checked
Result port. Final Program assembly must retain these unresolved requirements
and connect their discharge to this exact source identity; wire identity and
execution authority remain separate.

`close_program_expressions` closes the recorded typed-expression obligation
inventory for that same owned source identity. It exhaustively matches
`ProfileAdmission`, `PatternValidation` and `HostEnvelope`; adding another kind
requires updating this boundary rather than silently skipping it. Every pattern
and output-envelope resolution must refer to the exact context and occurrence,
including repeated producer visits and unselected branches. Counts must cover
the full prepared resolution collections, so neither missing entries nor extra
unconsumed results count as completion. Profile requirements consume the
preparation's already checked complete-profile declaration, not a new flag or
a certificate of backend conformance.

The opaque closure retains the source identity and exposes each requirement's
original site and its existing resolution through indexed reads. A lowerer need
not rejoin separate arrays or rediscover which producer/bound Parameters/policy
the result belongs to. Output bounds retain their original demand and policy
dependencies; they do not claim that runtime enforcement has run. One inclusive
work cap and an independent retained-entry cap are checked before allocation,
and the scan is linear in recorded occurrences. Empty inventories still retain
their owner and do not manufacture execution authority.

Operation-level inventories use [indexed obligation reads](operation-obligation-reads.md)
so collection can charge retained-entry budgets before allocating arrays.
Listing those obligations alone neither classifies nor discharges them.

`collect_program_operation_requirements` starts from the owned expression
closure and visits every stage, producer visit and local step, including unused
operations. Its opaque inventory keeps that closure and each entry's exact
checked pipeline, local group and typed requirement. Group scopes distinguish
Graph union folds and nested selectors rather than merging their obligations.
Repeated visits remain distinct even when they share the same pipeline owner.
Coordinates are local ownership coordinates, never semantic identity preimages.

Collection shares the upstream work total and charges stages, visits, steps,
groups and retained entries. Both work and entry caps are checked before entry
allocation; empty groups and inventories still incur traversal work. Failure
does not expose a partial inventory. The factory accepts no separately supplied
pipeline, obligation or identity, so a same-shaped foreign producer cannot be
attached through this boundary. Resolution remains a subsequent obligation:
the inventory is not a completed operation closure or an executable Program.

### Contextual order links

`link_program_operation_orders` consumes the owned inventory and attaches the
existing contextual resolution to each applicable order requirement. It selects
the original stage's producer visit and checks the exact pipeline owner before
reading local step resolutions. It never calls a key or order resolver again,
accepts an independent proof array, or substitutes an equal-looking producer.
The result retains the complete inventory, including requirements outside this
pass, and exposes the original occurrence index and resolution through indexed
reads.

The explicit demand classification separates authored sort/top-k/group-local
completion, take or pivot's stable sequence, lag key completion, prefix watermark
input order, analytic positions and nest's child order. Sort retains its chosen
candidate-key or inherited-tie strategy. Group requirements share the completed
group-order owner, which retains each individual aggregate resolution; they do
not acquire a group-output order. Analytic peer ordering and runtime top-tie
checks are not position completion and are not discharged by these links.

The underlying contextual resolver must already have resolved all its consumers,
including unused branches. A required strategy missing from that same step is
an error, not a runtime fallback. Incompatible multiple strategies are not
silently chosen. Empty sort produces no order requirement or new proof.
Conditional key validation, inherited-witness dependencies and runtime
enforcement remain attached to the retained resolution.

The work limit includes the original inventory and a charged pass over its
entries. A step's resolution list is indexed once into bounded strategy slots
before linking any repeated aggregate requirements; collection is linear rather
than rescanning that list for each requirement. Retained-link limits are checked
before allocation. This pass links contextual order decisions only, not the
remaining value, capacity, profile, policy or runtime implementation obligations.

### Bound scalar domains

`check_program_operation_scalars` validates scalar Parameter requirements from
the same owned operation inventory after contextual order linking. Declaration
admission is not enough to prove an operation-specific range: a number Parameter
can hold a fraction, an unsafe integer, or (if nullable) null.

The explicit domain classification covers `BoundInteger` with its own minimum,
`BoundFraction`, `BoundFinite` and `BoundDuration` from relational and sequence
row validations. Counts and offsets use exact safe integers without rounding;
zero is allowed only where the recorded minimum allows it. Fractions include
both endpoints of [0, 1]. Fixed watermark thresholds permit negative and
fractional finite numbers. Negative zero is rejected, not repaired. Duration
tokens use the existing positive safe-integer millisecond parser, preserving
the admitted original string and Parameter identity alongside the resolved
milliseconds.

Each result retains the exact requirement occurrence and admitted BoundParameter
from that producer's selected used-value index. Lookup checks the pipeline owner,
does not accept an independent binding set, and uses bounded binary search over
the name-sorted index rather than copying values or repeatedly building maps.
The shared work budget includes the preceding order links, requirement visits,
name comparisons and complete duration scans before parsing. Resolution caps
are checked before retaining entries. A later invalid value discards earlier
partial success.

These checks follow the literal domains in [take](../spec/language.md#take),
[aggregates](../spec/language.md#group), and
[relational temporal operations](../spec/language.md#relational-temporal).
They do not evaluate row expressions, establish actual counts, or claim resource
enforcement. Frame endpoint relationships, pivot fill compatibility, and other
operation families' specialized bound arguments remain separate requirements;
absence from this scalar-domain pass is not their discharge.

The same pass covers window `BindMilliseconds`, session `BindGap`, and time-series
`BindStep` requirements. Window offsets use the signed safe-integer domain;
size, step and session gaps require positive safe integers. Existing temporal
declaration admission permits only non-null number or duration Parameters.
For those owned bindings, duration tokens resolve to positive integer
milliseconds and numeric values stay exact integers. A signed offset does not
admit a negative duration token, fractional number, negative zero or overflow.
The result retains the original binding alongside its resolved milliseconds.

The [fixed-window step rule](../spec/language.md#event-windows) applies even
though the step does not affect boundary or cardinality calculations: its bound
value is still checked. The inventory is traversed regardless of downstream
demand for a capacity proof, so unused temporal operations do not bypass these
domains. Timestamp endpoints, relative range checks, window arithmetic and
session observations remain separate obligations; resolving milliseconds does
not imply that they have passed.

Series and Calendar `BindTimestamp` requirements retain only already-admitted
timestamp values. A string with the same spelling is not a timestamp binding;
no coercion or Host date parser is used. These scalar resolutions alone do not
establish calendar-year validity or interval ordering.

The scalar-domain classification also includes output guards for join,
cross/interval/as-of join, nest, Graph operations, traversal and shortest paths.
Their counts are positive safe integers. Graph bound-report counts retain their
separate nonnegative domain. Sequence `within` and as-of `tolerance` use the
positive millisecond domain shared with session gaps. Classification explicitly
lists each family's remaining obligations so new variants require review.

A valid guard value is not an enforced limit or an admitted capacity witness.
Cardinality, item-limit resolution, output enforcement, top-tie rejection,
membership and resource requirements remain in the same inventory. In particular,
the existing capacity integration may reject an incomplete proof collection
before this later scalar pass is reached; scalar admission does not weaken that
earlier boundary or manufacture the missing proof.

### Bound ROWS frame order

`check_program_operation_frames` closes `BoundFrameOrder` after scalar admission.
It obtains the analytic frame from the requirement's exact pipeline step and
checks that the original frame cursor owns the requirement. Symbolic distances
are read from that producer's existing selected Parameter bindings, never from
an independently supplied value map. The result retains both distances, each
bound Parameter and the original frame and requirement occurrence.

For two preceding boundaries, the start distance must be at least the end
distance; for two following boundaries it must be at most the end distance.
Equality is valid. Distances are compared as exact integers, without converting
to signed floating offsets. This implements the
[analytic ROWS rule](../spec/language.md#analytic), not a new acceptance policy.
Literal relationships and different boundary classes are already checked during
operation admission. Identical symbolic endpoints need no separate comparison
but still require positive safe-integer scalar admission.

The cumulative work budget includes the scalar pass, inventory traversal and
bounded name lookups. Resolution limits apply before retaining a result, and
any later failure discards all partial results. This closes only the boundary
relationship: frame demand, aggregate observations and runtime enforcement remain
separate obligations. Pivot fill compatibility is also a separate requirement.

### Bound pivot fill

`check_program_operation_fills` closes `BoundFill` after frame checks. It locates
the pivot through the exact requirement's pipeline step and checks the original
fill cursor and Parameter name. The selected binding comes from that producer's
owned index, not a separately supplied value or declaration map. Each resolution
retains the original pivot, requirement, admitted BoundParameter and target type.

Parameter binding already validates every value against its immutable contract.
Bounded assignability checks confirm that this contract satisfies both the
pivot's retained declaration contract and its result contract. This transfers
the existing value-admission evidence without reconstructing a JSON tree,
coercing a decimal, re-expanding nested Parameter-like data, or reapplying a
default. Nullable values remain nullable; a missing binding is not NULL.
The [pivot fill rule](../spec/language.md#reshaping) applies even with no generated
columns and is independent of whether a runtime bucket actually needs fill.

The cumulative work budget includes all preceding checks, index/name lookups,
contract nodes and text comparisons. Iterative contract scans reserve child
slots before growing the work stack; bounded type relations then charge their
actual pair visits. Output caps are checked before retaining resolutions. There
is no partial success on a later failure. This does not discharge partitioning,
aggregate demand, resource envelopes or actual runtime observations.

### Bound temporal ranges

`check_program_operation_ranges` links time-series `ValidateRange` and Calendar
`ValidateBoundRange` to their exact pipeline operations after fill checks. Both
endpoints come from the checked operation: literals keep their prior admission
evidence, and Parameters are obtained from the same producer's selected binding
index. The result retains each endpoint, optional BoundParameter and original
requirement occurrence. Independently supplied endpoint or proof arrays cannot
construct this result.

Canonical fixed-width UTC timestamps sort lexicographically in chronological
order. The check therefore compares the admitted strings directly, without
floating timestamp arithmetic or host timezone conversion. Reversed intervals
fail and equal endpoints are valid empty intervals. The
[Calendar domain](../spec/language.md#calendar) excludes year 0000, including
bound endpoints of an empty interval; the ordinary
[time-series domain](../spec/language.md#time-series) retains it. Parameter
declaration admission alone does not establish this Calendar-specific domain.

Work is cumulative through all preceding checks and includes inventory visits,
endpoint lookups and bounded string comparisons. Resolution limits apply before
retaining results; any later error discards partial success. This pass does not
generate rows or calendar boundaries, derive a row count, prove TZDB coverage
for generated boundary arithmetic, or enforce resource ceilings. Those remain
distinct obligations of the retained operation and selected profile.

### Vector query binding and dimensions

`check_program_operation_queries` closes `BindQuery` and `MatchDimensions` for
`score_vectors` after temporal range checks. It obtains the query and Vectors
dimension from the same checked operation and looks up a symbolic query in that
producer's owned Parameter index. Nonempty finite numeric components and exact
dimension equality follow the [vector query contract](../spec/language.md#vector-bridges).
An admitted array declaration without an exact length is not dimension evidence;
empty and mismatched bound arrays fail even though Parameter admission succeeded.

Literal query components have O(1) count/index access; Parameter components stay
in the original immutable admitted array. Neither path materializes a second
component array. The opaque admitted query offers bounded indexed reads and
retains the checked operation and optional BoundParameter. A query's binding and
dimension obligations share one component scan within a producer visit, but
separate producer visits retain separate resolutions and charges. Each link
keeps its original requirement occurrence.

Work is cumulative and reserves all component visits before scanning. Entry
limits apply before query preparation; a later mismatch or budget failure does
not expose a partially admitted result. This boundary preserves binary64 source
components but also verifies that their binary32 nearest-ties-even admission is
finite, as required by the pinned [numeric law](../spec/language.md#vector-arithmetic).
`operation_query_quantized_at` provides the admitted component widened exactly
to binary64 without allocating a second array. It preserves internal signed
zero; source components and identity preimages are not replaced by these reads.
Underflow to a zero vector is permitted for scoring and is not a normalization
success claim. This does not discharge the separate VecA arithmetic/profile
obligations: input-corpus component admission, zero-vector behavior, score
calculation, identity uniqueness and
execution resources must still be satisfied before scoring. Dimension admission
alone is not execution permission or validation of the input corpus's data.

### Finite Relation cell bindings

`check_program_operation_cells` closes each `REL.values` `BindCell` occurrence
after query admission, following [execution binding](../spec/language.md#rel-values-execution).
The operation, indexed cell and selected Parameter all come from the same owned
Program and producer visit. Repeated holes retain separate row/column and
requirement positions; equal names never collapse occurrences or transfer a
binding from an unrelated producer.

Parameter admission already checked the concrete immutable value. Bounded
assignability checks transfer that evidence to both the cell's retained
Parameter declaration and its column contract. No second value tree, wire JSON,
implicit cast, normalization repair or recursive `$param`/`literal` expansion
is performed. Decimal coefficients, null and nested business values remain in
their admitted representation. Literal quotation was resolved once by the
source checker and does not create a Parameter binding obligation.

The opaque result retains the preceding context and every resolution, including
the exact checked operation, source cell, target contract and BoundParameter.
Indexed cell access avoids scanning all rows for each obligation. Work includes
name lookup, recursive type traversal and both type relations; output entry
limits are checked before preparing a resolution. Failure exposes no partial
success. This does not construct execution params, serialize typed values or
discharge publication-resource obligations. Those boundaries retain their own
contracts and checks.

### Environment-owned lexical profiles

`check_program_operation_lexical` connects finite-cell checking to the selected
lexical artifact. The supplied `SelectedTextRankProfile` must retain the exact
Check Environment already selected by this Program, not merely an equal CID.
An absent artifact never bypasses validation of a supplied selection component;
malformed selections and selected-but-missing artifacts fail even when unused.
Absence of both remains valid for Programs without a lexical consumer.

Every step in every stage/producer visit is inspected, including unpublished
branches. Each `text_rank` receives a resolution retaining its checked operation,
coordinates and selected artifact. If the operation already holds a profile,
its CID must match the independently selected artifact; otherwise the retained
resolution supplies the missing association without mutating the operation.
Lowering consumes this association rather than selecting or inferring a profile.
Work accumulates over preceding checks, selection validation and all visits;
entry limits apply before retaining resolutions, with no partial success.

This closes lexical profile selection only. Complete input admission,
tokenization, BM25 arithmetic, rank generation, scoring ceilings, authority and
publication remain distinct requirements. Artifact input bytes are separately
bounded by the profile admission API; traversal work is not a heap-size bound.

### Environment-owned Calendar profiles

`check_program_operation_calendar` follows lexical profile resolution and
inspects every Calendar operation across all stages and producer visits. Its
selected transition artifact must belong to the exact Check Environment already
owned by the Program. Each operation's admitted table CID and external TZDB
release must agree with that selection; an already checked operation is not
permission to use a different table. The fixed conversion law is checked during
artifact admission, not selected again by the lowerer.

Absent selection is valid only without a Calendar consumer. A supplied selection
without admitted bytes, malformed unused selection, foreign environment or
operation/profile mismatch fails atomically. Resolutions retain exact checked
operations, coordinates and the selected artifact, with cumulative traversal,
comparison and output-entry limits. They do not replace source values, rerun
boundary calculations, or imply that runtime range/coverage checks, row counts
and resource enforcement have succeeded. Profile input ceilings remain separate
from Program traversal work. The lowerer consumes these resolved associations
instead of choosing a timezone database or trusting a profile support flag.

### Operation profile obligation links

`link_program_operation_profiles` connects explicit `Resolve…Profile` demands
to the existing owned `OperationProfileChecks`. The typed demand selector covers
the operation-obligation families explicitly; its `None` means only that the
requirement is not a profile demand, not that it is satisfied or belongs at
runtime. SGA/TEA/VecA demands must also occur in the checked operation's own
profile list. No new checker declaration or Host support flag is accepted.

Text-rank additionally consumes the exact operation-level lexical resolution,
including its selected environment-owned artifact. Stage, producer visit, step
and operation owner must agree. The two owned collections have the same traversal
order, so a single cursor matches lexical sites without repeated searching or
constructing string keys; every lexical resolution must be consumed. The prior
Calendar association remains attached even though its obligation enum has no
separate `ResolveProfile` variant.

Each resolution keeps its original requirement index/site and checker proof,
plus the lexical association when applicable. Work covers the inherited context,
every requirement visit and bounded profile comparisons; retained resolutions
have one aggregate cap. Failure exposes no partial collection. Indexed reads
do not copy operation bodies. This closes only these static profile associations:
it is neither backend conformance nor resource, value, identity, order or runtime
admission. All other obligations remain available in the retained inventory.

### Resolution coverage index

`index_program_operation_resolutions` maps the order, scalar, frame, fill,
range, query, cell and profile results back to their exact original requirement
occurrences. It consumes the single owned profile chain, not independently
supplied resolution arrays. Duplicate assignments and foreign occurrences fail
atomically. Required slots and every resolution visit are charged before index
allocation; construction is linear in requirements plus resolutions, and reads
are constant-time without copying the retained proof collections.

Each valid slot is explicitly `Resolved(typed resolution)`,
`Execution(typed check)` or `Unresolved`.
An absent indexed result means only an out-of-range index. `Unresolved` does not
mean runtime: a later coverage boundary must connect an allowed execution check
to its subject, application, dependencies and failure behavior, or reject static
unresolved/unsupported handling. Even zero unresolved operation occurrences do
not close input, publication, incoming, identity or other Program obligations.
Calendar and lexical operation-wide admissions remain owned by the retained
chain; they do not implicitly discharge arbitrary occurrence-level requirements.

For relational `dedupe_rows`, `DedupeTopTie` connects the owned `FailOnTopTie`
occurrence to its checked step, primary input target and exact checked operation.
Its rule is `aoa.rela.REL.dedupeRows.v0.1`, as registered in the shared primitive
laws and specified by [representative selection](../spec/language.md#distinct-and-dedupe).
The check is required before operation output publication; any unresolved top
tie rejects that operation's output under
[operation atomicity](../spec/execution.md#capture-and-replay).
It is not a claim that any rows have already passed.

The retained operation supplies authored partition keys and order terms through
bounded indexed readers, including repeated keys and a global empty partition
key. No candidate-key completion, arrival order or CID tie-break is introduced.
The input target is interpreted only in the retained pipeline and producer visit;
its input admission and producer dependencies remain prerequisites, not proofs
manufactured by this binding. Other families, including event deduplication,
are not implicitly covered by matching a similarly named obligation. Backend
support and complete Program dependency coverage remain separate checks.

### Joining incoming and operation checks

`link_program_incoming` joins the incoming-requirement inventory with the
operation-profile chain only when both retain the exact same
`ProgramSourceIdentity`. Matching public Definition or Parameter Values CIDs
does not establish this in-process ownership. Reissuing a source identity
therefore cannot substitute one branch for another, while rebuilding an incoming
inventory from the original identity is permitted.

The opaque result retains both original branches without copying their arrays.
It constructs and retains the occurrence resolution index internally, including
connected execution checks and explicit unresolved slots. It does not accept a
substitute index from the caller. Index allocation and traversal use the same
aggregate work budget after reserving the incoming branch's additional work;
the incoming name and occurrence caps keep their original meaning.
Its work includes both branches, counts the common identity prefix once, and
charges the join itself. Incoming name and requirement limits remain enforced;
subtract-before-add accounting rejects over-budget joins without integer overflow.
This connects stage dependencies to the operation checks, but does not discharge
incoming success/receipt requirements, issue Unit or Invocation identities,
resolve missing resource contracts, or constitute the final `CheckedProgram`.

Expression closure does not discharge operation-level obligations, bind
authored guard witness identities, build staged Program/import contracts, or
complete local Unit/Invocation identity projections. Source Program and stage
semantics are provided by the owned identity projection, not evidence that those
other checks passed. A formal compiler
entry must still close those requirements before lowering. Internal ownership
and producer coordinates are not persistent identities.

Conditional keys, actual uniqueness, input admission, observed counts and limit
enforcement remain obligations of their retained evidence, not completed runtime
checks. The result grants no execution or publication permission. Lowering must
not treat this intermediate context as the final `CheckedProgram`, invent missing
static decisions or independently replace main's remaining integration.
