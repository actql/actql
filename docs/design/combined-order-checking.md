# Combined pipeline and Result order checking

`relation_results.resolve_all_orders` resolves the contextual order requirements
of every pipeline step and every retained producer pipeline, followed by every
named root Result publication strategy. Its
single input is `CheckedResults`, which already retains its original pipeline;
there is no separate pipeline argument that could pair foreign evidence.

Step and Result counts are checked before traversal. `max_steps` covers the sum
of step occurrences across the root and all producer visits. Work and text-byte
budgets are shared: the publication resolver receives only what remains after
producer closure resolution. An unused branch cannot bypass a required order check,
and a later failing Result cannot expose a partial successful collection.
`PipelineOrder` and `ResultOrder` retain their original located diagnostics,
including embedded expression ranges where the pipeline issue carries one.
Invalid limits and collection caps are reported at the Results source.

The opaque `CheckedOrders` retains the producer closure and publication results
and their combined usage. `checked_contextual_orders` continues to expose the
root's context; `checked_producer_orders` exposes the complete closure. Their
root pipeline is identical, not merely structurally equivalent. Individual
resolvers remain useful for diagnostics and
inspection, but are not substitutes for this aggregate boundary when checking
all required order consumers of a published pipeline.

## Producer closure

`pipeline_typing.resolve_contextual_closure` visits the root followed by producer
inputs in declared depth-first order, using an explicit stack. Every retained
input is inspected, including unused inputs; every visited pipeline resolves all
its steps, including branches that do not feed the imported target. A repeated
producer is checked and charged per reference occurrence. There is no implicit
deduplication or unbounded identity-comparison cache. Public construction of
these immutable owners only references already checked pipelines, so it cannot
create a cycle.

Each visit charges one work unit plus its input count before adding parents to
the stack, then the contextual resolver consumes the remaining work/text budget.
Even empty forwarding chains and shared ancestry are bounded. Step limits and
aggregate text budgets do not reset between visits. The returned closure retains
each occurrence's context, total steps and combined work/text usage. Errors
carry the actual failing pipeline with its original located issue. Root failures
remain `PipelineOrder`; upstream failures are `ProducerOrder`. No partial closure
or publication result is returned after a later failure.

Regression coverage includes a selected valid output whose producer has an
unused unresolved branch, an entirely unused bad producer input, repeated owner
occurrences, shared aggregate text limits, and a 2,000-link non-recursive chain.

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
