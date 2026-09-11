# Graph input capacity binding

`capacity_graph_preflight` binds Host-backed node and edge input limits to an
immutable `pipeline_typing.CheckedPipeline` and an explicitly selected admitted
`capacity_policy.Policy`. This is static consumer association, not execution of
preflight or admission of measured counts.

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

## Combined Graph, sequence and join consumer coverage

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
against the same Graph input owner. Its optional join ledger must retain the
exact Program application table supplied to source coverage; an independently
constructed table with the same claim collection is not interchangeable.
This prevents candidate availability from being checked against one table while
source completeness is certified against another.

The work budget is shared: source scanning consumes one unit per witness, then
consumer scanning receives only the remainder. The opaque result retains both
checked results and their summed work. A late unconsumed limit or short consumer
budget returns only an error, never a partial combined result. Source and
consumer diagnostics remain distinguished. Regressions include an unsupported
Contract source even with no consumers, proof-table substitution, an omitted
join ledger, unused limits and exact/short combined budgets.

This entry closes composition for the supported source and consumer branches;
it is not full pipeline readiness. Selected-policy authority, enclosing
Program/Invocation identity, author and other external sources, remaining
operation consumers and upstream closure are still required separately.
