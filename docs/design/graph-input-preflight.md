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

The selected policy remains caller-selected; this layer does not authenticate
Host authority. It neither reads a Graph nor executes a preflight, creates a
runnable Plan, checks every other limit consumer, or discharges all pipeline
obligations. Final combined checking must retain these distinctions and validate
the remaining consumers before claiming execution readiness.

Tests use independently hashed fixed wire artifacts and cover both measures,
repeated candidates, exact budgets, foreign scopes, incomplete and duplicate
bindings, unsupported candidates, opaque Graph inputs and unused inputs.
