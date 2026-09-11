# Combined pipeline and Result order checking

`relation_results.resolve_all_orders` resolves the contextual order requirements
of every pipeline step followed by every named Result publication strategy. Its
single input is `CheckedResults`, which already retains its original pipeline;
there is no separate pipeline argument that could pair foreign evidence.

Step and Result counts are checked before either traversal. Work and text-byte
budgets are shared: the publication resolver receives only what remains after
contextual resolution. An unused branch cannot bypass a required order check,
and a later failing Result cannot expose a partial successful collection.
`PipelineOrder` and `ResultOrder` retain their original located diagnostics,
including embedded expression ranges where the pipeline issue carries one.
Invalid limits and collection caps are reported at the Results source.

The opaque `CheckedOrders` retains both existing opaque resolver results and
their combined usage. Their underlying pipeline is identical, not merely
structurally equivalent. Individual resolvers remain useful for diagnostics and
inspection, but are not substitutes for this aggregate boundary when checking
all required order consumers of a published pipeline.

This resolves static order **strategies**, not observations about row data.
Candidate-key declarations, producer checks, tie failure, input validity and
other execution/binding obligations remain attached. Capacity source/law
validation and enforced resolved limits are not discharged here. The final
all-obligation boundary must combine this result with those checks; this type
does not grant permission to execute or publish.

Regression tests cover unused unresolved steps, a later unresolved Result,
identity of the retained pipeline, exact count/work/text budgets, and aggregate
plus publication name processing under a shared text budget. A budget that
would suffice for either phase in isolation is not reused for both phases.
