# Integrated pipeline checking context

`pipeline_check_context.check` constructs an opaque `PipelineContext` by running
the existing order, binding and capacity integration boundaries together. It is
a main-side building block for the
[pre-lowering Program boundary](pure-operation-checking.md#main-and-lowering-ownership),
not that completed boundary and not a Check Environment artifact or CID.

## Construction and ownership

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
