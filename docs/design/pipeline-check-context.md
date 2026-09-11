# Integrated pipeline checking context

`pipeline_check_context.check` constructs an opaque `PipelineContext` by running
the existing order, binding and capacity integration boundaries together. It is
a main-side building block for the
[pre-lowering Program boundary](pure-operation-checking.md#main-and-lowering-ownership),
not that completed boundary and not a Check Environment artifact or CID.

## Construction and ownership

The constructor starts with `relation_results.CheckedResults`; its retained
pipeline determines the root. It resolves all contextual producer orders and
root publication orders, binds guard quantities for every producer occurrence,
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

The result retains checked Results, resolved orders, bound guards and capacity
closure through read-only accessors. The constructor does not retain caller
arrays. Errors preserve the originating order/binding/capacity diagnosis,
including the failing producer. A late failure exposes no partial context.

## Cumulative limits

Step and Result caps are passed to whole-closure order resolution. Work and
text budgets are shared: order resolution consumes first, guard binding receives
the remainder, and capacity closure receives the remaining work. Successful
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

## Not yet a checked Program

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
