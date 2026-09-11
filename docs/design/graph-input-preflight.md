# Graph input capacity binding

`capacity_graph_input` binds Host-backed node and edge input limits to an
immutable `pipeline_typing.CheckedPipeline` and an explicitly selected admitted
`capacity_policy.Policy`. This is static consumer association, not execution of
preflight or admission of measured counts.

`capacity_graph_preflight` retains the existing entry points and types as a
facade, and composes source/consumer coverage above Program applications. Input
admission itself has no dependency on those application packages. This permits
application inputs to retain an admitted input owner without a dependency
cycle. `input_bound` selects the validated node or edge witness by input index;
the opaque bound retains its original `GraphInputs` owner, including the policy,
source collection and `unit_preflight` obligation. It does not create measured counts.
The opaque result is shared, not copied or reconstructed by the facade. Coverage
uses indexed input-limit access and preserves the previous budget accounting.

The normative owner is [Resolved limits](../spec/language.md#resolved-limits).
The reference compiler's Graph input form uses `graph-input:<name>:nodes` and
`graph-input:<name>:edges` subjects, Program semantic references equal to the
input name, `actql.bound.graph-input-nodes` and
`actql.bound.graph-input-edges`, and `unit_preflight` enforcement. The respective
candidates are the selected policy's `max_graph_input_nodes` and
`max_graph_input_edges` Host ceilings. These associations are checked, not
inferred from equal numeric values.

## Ownership and coverage

The input is a collection-wide `HostSources` owner with mixed witness/limit and
Program dependency closure. Each enforced Graph input claim must resolve to an
actual Graph input and exactly match its subject, measure and selected policy.
Every candidate must be an already verified Host source for the corresponding
policy field. Repeated candidate occurrences remain intact. A same-valued
ceiling from another policy or field is not interchangeable.

Each Graph input needs exactly one node and one edge binding, including unused
inputs and opaque inputs whose Graph kind is known but whose structural details
are not. Non-Graph inputs do not need these bindings. Missing or duplicate
measures, unknown input names and wrong Carriers fail atomically. The returned
opaque owner retains the exact pipeline, source collection, policy and resolved
limits; it exposes no new observed-count evidence.

`capacity_program_step.check_with_sources` accepts these bounds alongside
ordinary operation applications. It matches the actual input occurrence, exact
pipeline owner and measure before applying a Graph bridge or structural law.
Imported input links are followed under the existing cumulative traversal budget;
matching names, values or witness CIDs cannot replace the producer owner.
The application collection requires an input bound's original `ProgramClaims`
owner, not a separately admitted collection with identical bytes. This preserves
conditional enforcement rather than asserting that preflight has already run.

`max_work` charges two visits per input, every witness and every candidate
occurrence of a bound limit. `max_name_bytes` charges each pipeline input name's
UTF-8 length once, including non-Graph names. Exact budgets succeed. Input count
is checked before allocating the index and binding arrays. Indexed pipeline
accessors avoid copying the full input array for each lookup.

## Deliberate limits

This entry covers the reference compiler's Host-backed Graph input form. It
rejects other enforced-law families and candidates whose non-Host source or
application is not yet validated. Those are implementation gaps, not language
prohibitions. Other resolved limits in the retained collection are not claimed
consumed merely because these Graph bindings succeed.

`unconsumed_limit_count` explicitly reports those remaining limits.
`check_complete` is the collection-complete variant: it applies the same
association checks and budgets, then rejects any remaining limit with
`UnconsumedLimits`. Each accepted input/measure has an exact unique subject and
duplicate measures are rejected, so the remaining count can be computed without
a second identity scan. Mixed witness admission alone may contain valid limits
without an enforced consumer; that is not sufficient for this complete variant.
Use partial `check` when other consumer families will account for the remainder;
do not interpret its success as complete limit consumption.

The selected policy remains caller-selected; this layer does not authenticate
Host authority. It neither reads a Graph nor executes a preflight, creates a
runnable Plan, checks every other limit consumer, or discharges all pipeline
obligations. Final combined checking must retain these distinctions and validate
the remaining consumers before claiming execution readiness.

Tests use independently hashed fixed wire artifacts and cover both measures,
repeated candidates, exact budgets, foreign scopes, incomplete and duplicate
bindings, unsupported candidates, opaque Graph inputs and unused inputs.

## Shared source coverage

`check_source_coverage` combines `GraphInputs` with the ordinary Program
application table from `capacity_program_step`. Both must retain the exact same
`ProgramClaims` owner; identical-looking separately admitted collections cannot
be substituted. Each claim must have either an admitted Host source, a checked
ordinary Program application, or a mixed enforced-limit association already
validated by the Graph preflight checker. This includes unused claims. Other
sources fail explicitly instead of being treated as trusted because their CIDs
and arithmetic are internally consistent.

The flat coverage scan costs one work unit per witness and retains both checked
owners without copying their trees. It does not change the selected policy's
authority status, establish enclosing Program/Invocation identity, or consume
additional limits. In particular `unconsumed_limit_count` on the retained Graph
result remains meaningful after source coverage succeeds. The combined result
is source-application coverage for this supported subset, not a runnable Plan
or a claim that Contract/Language source application has been implemented.

Regression checks cover exact scan limits, same-content foreign collection
owners, remaining unused limits, and a valid Contract wire claim whose source
body has not been admitted.

## Combined Graph and operation consumer coverage

`check_consumer_coverage` combines this partial Graph result with the complete
local sequence application table from [sequence capacity](sequence-capacity.md).
Both must retain the exact same pipeline and Host-source collection, and select
the same policy CID. It verifies each limit in that mixed collection has exactly
one consumer across the supplied families. An optional complete local join
application table from `capacity_program_step` extends the same scan to ordinary
join, cross join and interval join output limits. It must retain the same
pipeline, source owner and selected policy; omitted join applications cannot
consume any limits by implication. Graph input subjects and node/edge units
remain distinct from sequence per-key and total-output scopes.
An optional complete components table extends the scan to its input-node and
output-row limits, under the same owner and policy checks. These local operation
limits are separate from the input Graph's preflight limits even when their
units and numeric ceilings coincide.
Traversal has a separate optional ledger for its Paths search ceiling and Rows
output ceiling, checked against the same owners and selected policy. Both
node-emitting and path-emitting traversals require both limits.

The scan costs two visits per pipeline input binding and one per mixed limit,
checked before allocating a CID index. All indexed identities are admitted
fixed-width CIDs. Exact budgets succeed; missing consumers and duplicate
consumption fail atomically. The opaque result retains the original checked
owners, without changing their individual partial-coverage counts.

This closes mixed limit consumption for these supported consumer families,
including unused Graph inputs and local sequence branches. It is not whole
pipeline readiness: other operations' required limits, upstream producer
closure, author/Contract/Language sources and Host authority still need their
own checks. Source coverage is separately available and is not implied by
limit consumption. Runtime preflight and engine-atomic enforcement are retained
requirements, not executed by this static boundary.

Independent canonical wire fixtures combine four or five limits in one collection.
Tests cover typed and opaque Graph inputs alongside sequence, Graph-only
collections, a valid extra limit with no consumer, same-content foreign owners,
different policy selection and exact/short work budgets.
Join regressions also cover omission of the optional ledger, a foreign join
pipeline owner and an extra valid limit left unused after all three families
have been connected.

## Combined supported application coverage

`check_application_coverage` runs source coverage and mixed consumer coverage
against the same Graph input owner. Its optional join, components and traversal
ledgers must retain the
exact Program application table supplied to source coverage; an independently
constructed table with the same claim collection is not interchangeable.
This prevents candidate availability from being checked against one table while
source completeness is certified against another.

The work budget is shared: source scanning consumes one unit per witness, then
consumer scanning receives only the remainder. When any optional ledger is
absent, one additional scan costs one unit per local step and requires that no
operation belonging to that absent family exists, including unused branches.
The scan is shared when several ledgers are absent. Omitting both the application
and its limit artifacts therefore cannot pass this entry. An admitted family
ledger already carries its all-step coverage. The lower-level consumer
ledger scan remains artifact-consumption-only, not operation coverage.
The opaque result retains both
checked results and their summed work. A late unconsumed limit or short consumer
budget returns only an error, never a partial combined result. Source and
consumer diagnostics remain distinguished. Regressions include an unsupported
Contract source even with no consumers, proof-table substitution, an omitted
join ledger, unused limits and exact/short combined budgets.
Empty mixed collections are tested with all three join families, as well as
empty and non-join pipelines; only the latter may omit a join ledger.

This entry closes composition for the supported source and consumer branches;
it is not full pipeline readiness. Selected-policy authority, enclosing
Program/Invocation identity, author and other external sources, remaining
operation consumers and upstream closure are still required separately.

## Producer occurrence coverage

`check_application_closure` pairs one supported `ApplicationCoverage` with each
visit of the admitted contextual producer closure, in its existing root-first
depth-first order. The exact pipeline handle must match at every position;
equal source text or a matching input name is insufficient. Missing and extra
entries fail. This includes unused inputs and branches because the contextual
closure enumerates them rather than taking a caller-selected target subset.
Repeated producer references remain separate occurrences and are charged again.

The caller supplies the selected admitted policy independently of the local
applications. Every visit must retain that policy CID, including visits with
empty witness/limit collections; the first application's choice is not silently
adopted as the environment's choice. Different admitted handles for the same
canonical policy are equivalent here, unlike pipeline ownership. The closure
retains the explicitly selected handle through `application_closure_policy`.
This binds this closure to one Check Environment selection, following the
protocol's capacity-host-policy canonical-source rule. It does not authenticate
the selecting Host or claim that arbitrary independently checked producers must
share an environment before being submitted to this combined boundary.

The capacity aggregation budget is one registration unit plus the retained local
application work and a Program application-table scan per visit, using
subtraction before addition to avoid overflow.
It does not rerun or silently reset each local budget. The returned entry array
is detached, and a failure at a later visit returns no partial closure. Tests
cover repeated producers, an unused second input, equal-content foreign owners,
missing/extra entries, exact/short budgets and a 1,000-link forwarding chain.
Policy regressions reject both a foreign upstream selection and an independently
selected policy that disagrees with the root, even when all local limits are
absent or numerically unaffected by the changed policy field.

The required `bound_guards` argument must retain the exact same contextual
closure. Every visit's Program proof table is checked against its corresponding
bound guard context using `capacity_program_step.check_guard_bindings`; omitting
this comparison is no longer a successful capacity-closure path. Local proofs
that use Parameter values must retain that context's exact bound collection.
Repeated visits are checked independently and charged again. The result retains
the bound closure and each local comparison. Foreign producer entries in a
local proof table are checked by the subsequent membership pass.

A fixed, independently hashed take-bound fixture covers a producer referenced
twice, including an unused second reference. Substituting a different bound
value collection at the later visit fails atomically, as does a one-short scan
budget. Recomputing an otherwise identical contextual closure cannot substitute
for the bound guards' original owner. This is occurrence-local agreement, not
proof of enclosing Program semantic identity.

The membership pass visits every ordinary proof in every retained table.
Proofs owned by that visit's pipeline use the current visit automatically.
Nonlocal proofs require `proof_owners` coordinates `(table visit, claim index,
producer visit)`. Each coordinate must resolve to an ordinary proof and an
actual contextual visit whose pipeline is physically the proof's owner.
Missing, duplicate, out-of-range, mismatched and unnecessary local registrations
are rejected. The selected producer's bound Parameter collection must also
match any bindings retained by the proof. Coordinates cannot manufacture a
producer or establish ownership merely by matching source text.

Registration costs one unit each, followed by one unit per table slot, under
the remaining aggregation budget. Direct indices and a coordinate map avoid
searching every producer for every proof. The owned result exposes the resolved
visit through `application_closure_proof_owner`; mutating the registration array
does not change it. Tests cover nonlocal proof reuse, missing and invalid owner
coordinates, duplicate registration, equal-valued foreign binding collections,
and an exact/one-short membership budget. This establishes membership in the
submitted producer closure, not semantic Program/Invocation identity or Host
authority; normal proof-input checks still govern actual dependency edges.

Graph preflight dependencies are also checked against the registered contextual
coverage. A dependency whose exact `GraphInputs` handle is the proof owner's
registered preflight resolves automatically to that visit. Other roots require
`input_owners` coordinates `(table visit, claim index, dependency index,
producer visit)`. The target must hold that exact preflight handle; equal input
names, equal CIDs, or rerunning the same check are not substitutes. This is
ownership consistency of the submitted checks, not a restriction on rechecking
a Program with a newly assembled consistent set of owners.

The additional scan charges every table slot and every ordered proof dependency,
including repeated dependencies and tables, plus one unit per registration.
Missing, duplicate, out-of-range, unnecessary and foreign registrations fail
atomically. `application_closure_input_owner` exposes the retained resolved
visit without retaining the caller's registration array. Local and imported
regressions cover exact/one-short budgets and replacement of a preflight with
an independently checked identical input. The preflight execution obligation
remains on the retained input owner; membership does not claim it has run.

This establishes supported local capacity coverage across the producer graph,
not complete source authority or all capacity consumers. Contextual resolution
and the prerequisite local checks retain their own budgets; this aggregate is
not a replacement for the final all-obligation budget. Enclosing identity and
consistent parameter bindings within a Program/Invocation remain separate.
