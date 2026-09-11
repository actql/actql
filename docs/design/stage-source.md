# Source-bound stage local bodies

`stage_source.prepare` consumes one `stage_parameters.CollectedStage`. Its
source, stage index, Parameter declaration owner and checked pipeline cannot be
supplied independently. `Body` is opaque and retains that owner and the prepared
pipeline source. This is the `local_body` source projection described by
[Canonical identities](../spec/language.md#canonical-identities), not a checked
Program, stage semantics envelope, publication permission or executable plan.

The output contains inputs, steps, results and effects, with an explicit empty
effects map when omitted, and from only when authored. Stage id and after are
not part of this body. Imports remain explicit source references; captured
values are not substituted. Short-form Inputs are retained, without invented
schema/default expansion. Result order-key spelling and source no-ops remain
authored. Plan completion, evidence and journal entries are separate.

Allowed annotations are excluded only at the immediate Input, Result and Effect
declaration slots. Step annotations are handled by the owned `pipeline_source`.
Stage metadata was already admitted by `stage_syntax` and is outside local_body.
Newly excluded annotations must be nonempty objects with no top-level `actql_`
key. Their JSON scalar validity already follows from the opaque parsed Stage
source. No recursion interprets nested business keys as annotation or syntax:
payloads, set values and literals retain `meta`, `$param` and `literal` as data.

Update/delete where arrays are decoded using `selector_syntax`, so common text
and structured notation share the normalized source expression representation.
Effect wrappers must select exactly one known kind and where, when present on
these selector-bearing kinds, must be a nonempty array. The immutable selectors
are available by indexed access with their original path, span, text range and
unbound Parameter occurrences. No caller can inject a replacement expression.
Other Effect body fields remain source data. This does **not** validate complete
Effect bodies, selector field types, targets, mapping contracts or authority.
For example a syntactically projectable Effect missing its target is not thereby
a valid Effect. Full Input/Result/Effect admission remains required before an
identity-bearing checked Program can be constructed.

The preparation work budget includes prior stage collection work once, pipeline
source preparation, declaration/annotation indexing and retained raw source
traversal. Selector node, text-byte and token caps accumulate across all Effect
where elements; depth and owned-tree caps apply to each expression. These are
additional selector syntax limits, not a retroactive replacement for pipeline
typing limits. All failures return no Body. The source parser's own budgets and
full Program admission costs still belong to the enclosing integration boundary.

Emission uses the caller's canonical text, measurement or hash sink and shares
its enclosing byte/node/depth limits. Iterative source traversal and selector
emission avoid a second normalized stage tree. Object key sorting still requires
bounded temporary storage; max_bytes is not a whole-heap memory limit. A hash
sink can hash these bytes as part of a containing envelope, but this package
does not publish a stage CID API: complete used Parameter/Binding references,
declarations, environment admission and semantic envelope ownership are not yet
closed by this projection.

The specification is authoritative. Inspection at Sketch `87dc7144` found
source cloning and Effect selector decoding, not a complete staged local-body
owner to reuse. The implementation composes the existing owned stage/pipeline
and restricted selector boundaries rather than adopting older root-only
Program identity shapes. No new language acceptance rule or backend requirement
is introduced here.

Tests fix annotation scope, imports and after exclusion, absent effects, source
ownership, selector normalization and diagnostics, cumulative limits, malformed
annotations and ambiguous Effect wrappers, a depth-10,000 business value,
independent canonical bytes/digest and three-sink boundary equivalence. They are
source-projection evidence, not Effect evaluation or Program conformance.
