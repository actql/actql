# Integrated pipeline checking context

`pipeline_check_context.check` constructs an opaque `PipelineContext` by running
the existing order, binding and capacity integration boundaries together. It is
a main-side building block for the
[pre-lowering Program boundary](pure-operation-checking.md#main-and-lowering-ownership),
not that completed boundary and not a Check Environment artifact or CID.

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
It accepts one ExpressionValidationContext and constructs both component checks
itself; it does not accept timestamp and regex collections from the caller.
The opaque PatternChecks retains that same context and every resolution in the
original inventory order, including reused producer occurrences. The returned
PatternResolution enum exposes a read-only timestamp or regex result, not a
constructor for the owning checked collection.

The constructor first rejects any unhandled PatternValidation operation instead
of silently omitting it. It then checks timestamps and regex/static replacement
options, in that deterministic phase order. An error reports its component and
original inventory index. Result ordering does not claim a different global
first-error order across phases, nor runtime first-failure semantics.

All source/work caps include the retained base context exactly once. The second
phase receives caps reduced by the first phase's incremental cost, not by the
entire shared context. AST bytes and JSON nodes accumulate without overlap
because both phases construct distinct ASTs. Inventory preflight and ordered
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
It does not discharge every operation's static/profile/pattern obligation, bind
authored guard witness identities, build staged Program/import contracts, or
construct Program/stage/Invocation semantic projections. A formal compiler
entry must still close those requirements before lowering. Internal ownership
and producer coordinates are not persistent identities.

Conditional keys, actual uniqueness, input admission, observed counts and limit
enforcement remain obligations of their retained evidence, not completed runtime
checks. The result grants no execution or publication permission. Lowering must
not treat this intermediate context as the final `CheckedProgram`, invent missing
static decisions or independently replace main's remaining integration.
