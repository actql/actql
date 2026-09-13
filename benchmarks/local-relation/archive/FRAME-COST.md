# Bounded frame/event cost investigation

> Historical snapshot, not current status or authorization. Start with the
> [integrated report](../REPORT.md). Past stops and pending approvals below
> describe only the stage at which this document was written.

## Authorized experiment

Following the stopped historical run, the user authorized representative
attribution and one local improvement pass, not repeated optimization until
every uncertain condition passes. The full-matrix gate is not relaxed or
claimed by this diagnostic.

Freeze the shared main base at `7b655eb`. Compare rebased `bafdc88` (before)
to `fdf2723` (frame extraction), and `fdf2723` to `1f2b981` (shared events).
The latter changes to production execution are the event/row handoff extraction;
test-only trials and reports do not select another production backend.
Use identical four-file profiling overlays on detached ignored worktrees.

Fix four 1,000-row workloads before measurement: numeric projection,
conditional IF/CASE, eight ordered slots, and 64-addition expressions.
Measure native and JS, E2E and prepared, exactly seven alternating pairs per
cell (224 processes per comparison). No automatic uncertainty extension or
threshold gate follows; retain uncertainty in the report. Wasm correctness
remains covered by tests but Wasm performance is not measured here.

After attribution, permit one local change in `expression.mbt` and/or
`expression_events.mbt`, with associated non-public frame tests and design
documentation. Keep shared demand/charge/root events, resumability, all
failure precedence and ownership rules. Do not change driver, completion,
lowering, typing, contracts or logical accounting laws. Record the selected
change before editing it. Compare the improved revision against `1f2b981`
using the same subset, and report absolute as well as proportional residual
cost against the pre-extraction baseline. No second tuning pass is implicit.

Validate the whole three-target tests/checks with warnings denied, API,
format, documents and metadata after the product change. Report and stop
for the user's decision on remaining cost versus the retained boundary.

## One selected improvement pass

Attribution completed 224 invocations per comparison. Frame extraction raised
prepared paired medians roughly 7–9% on native and 8–10% on JS. Event extraction
had workload-dependent cost: native expression-heavy cases rose about 8–13%;
JS was smaller in some cases. These are incremental observations, not exact
additive causal percentages; host variation and generated-code changes remain.

Edit `expression.mbt` to let the synchronous caller drain the existing transition
loop within one call, retaining the single-step entry and the same events and
terminal cleanup. Edit `expression_events.mbt` to consume two operands and
release their two roots directly in the original order, without constructing
two-element temporary arrays. This retains one semantic implementation and
does not flatten lazy branches or reorder accounting. Add frame tests that
compare stepped/drained execution at each small logical/control budget,
including terminal reuse and borrowed-root lifetime. No other tuning pass
is included in this authorization.

## Result

The bounded pass and correctness checks are complete. See
[the one-pass results](FRAME-COST-RESULTS.md) for all representative cells,
residual absolute cost, uncertainty, retained boundaries and the next decision.
This is not full performance acceptance or completion/producer implementation.
