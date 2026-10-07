# Captured Result preparation without an extra Client selection

## Completion unit and dependency

Parent #907 is `68af65e2a68dfaedaabbb120c7dcc194370108fd`, itself dependent
on #904. The adopted main remains
`2664bcf3203c42eafe0ca5919763dbe8ad081b40`. The parent was open and unmerged
when this unit was prepared for publication. The final merge destination is
main, after the parents are adopted; do not merge this child into a dependency
branch as a substitute for main integration.

Previously `outputExportControl.beginResult` polled the common preparation
only when an additional `ClientResultTransformation` was supplied. Without
that optional selection, it called blocking Result export preparation. The
managed import completion branch also selected a blocking export. These were
adapter connections to existing bounded algorithms, not missing kernels.

An absent Client selection is not an absent checked Result occurrence. The
captured graph still supplies its exact ResultPort, producer, projection,
publication order and definition. Both paths now poll the same existing view
owner rather than route through the blocking convenience entry points.

## Ownership and production connections

The implementation source is
`2b05d8f1d3c007549ac1ceb95d9c5ed64ca40722`.

- `run_publication_host/client_result_transformation.mbt` separates the common
  preparation's occurrence/definition from the optional extra Client selection.
  `start_result_publication_export` starts the existing
  `CompletedResultRelationExportPreparation`; it does not add a serializer,
  execution algorithm, scheduler or ledger.
- `client_captured_result_transformation.mbt` adds
  `start_captured_result_publication_export` and
  `start_captured_managed_result_publication_export`. Both retain the existing
  `CapturedClientResultTransformation` custody. Selected callers first verify
  their exact prepared graph and Result index, then use the same connection.
- Acquired Sources use `start_captured_any_result_borrow_export` with their
  existing restricted source/pin. Cells use their exact completed generation;
  an unrelated converted output is still rejected. Managed rows require the
  existing live bridge/managed-completion/export ownership match, not equal
  schemas or content CIDs.
- `scripts/templates/strategy-node.mbt` drives the same opaque preparation
  whether the extra Client selection is present or absent. Generated Node,
  RelA and Workers bridges/interfaces come from the real template/generators.
- `adapters/host-common/runtime-core.mjs` polls that preparation for every
  `beginResult` and managed Result import completion. Caller cancellation is
  passed from `strategy.mjs` and `durable-result-payload.mjs`, checked before
  acquisition, between polls and before final stream transfer. Failure cancels
  the same preparation; no synchronous fallback is attempted.

An in-flight Result pin transfers once to `PublicationOutputExport`, or returns
through its existing cancellation path. Cancelling preparation after successful
transfer cannot revoke the exported Result. Repeated finish cannot issue a
second owner. Closing the ordinary producer port does not revoke the retained
consumer. Native convenience callers that explicitly drain preparation were
not silently converted to a new execution system.

No language, value, ordering, wire, CID, policy or product-capacity changes were
made. Existing work/workspace accounting belongs to the same Result view and
schema owners, not a new per-adapter budget or poll-count estimate.

## Independent evidence

Before the adapter change, the three new control regressions failed in
`run-3XjBZ1` / `focused-test-talvRN`: two captured cases selected the old blocking
begin instead of the registered bounded fixture, and managed completion called
the explicitly forbidden synchronous finish. This is a routing counterexample
using an adapter fixture, not a claimed public Run calculation failure.

Focused common tests cover:

- Cell exports with quanta 1/7/64: positive progress, cancellation and pin reuse,
  ordinary producer-port close, exactly one transfer, independent rows
  `[{"id":3},{"id":2}]`, and final zero held bytes.
- Acquired Source exports: a one-row ceiling rejects the independently expected
  two-row Result with `Transform(Output(Admission(CaptureLimit)))`. Cancellation
  returns its only pin. A later preparation completes the original acquisition
  without Compute and yields independent rows `[{"id":2},{"id":3}]`.
- Managed bridge exports: an unrelated bridge is rejected; cancellation and
  typed order-work refusal return the pin; success yields independently fixed
  ascending rows. Existing selected transformations, ordering evidence and
  independent publication/Effect consumer retention remain covered.

Actual Host cases use normal Program preparation, installed Local execution,
real retained/publication Stores and two downstream consumers. The new pair
omits only the legal optional Client selection from the publication request;
it does not replace the captured graph or manually construct a completion.
Two independently authored object payloads each contain 65 numeric properties.
All three committed Result names are read and compared with exact payloads
and `id DESC` order, not merely an occurrence count or unordered row set.

The cancellation case observes positive progress inside the real recursive
schema cursor before scheduling cancellation. It preserves the exact original
cause, publishes no committed index, cancels the pending borrow once, and
returns retained/read/execution/publication reservations to zero. Compute
dispatch count stays three through cleanup. All Compute tasks are already
physically complete at this boundary; this is Result preparation cancellation,
not a proof of Compute stop delivery or a new Run terminal classification.

The parent's explicit 4096-byte nested-value fixture policy remains unchanged.
These are non-tight success/cancellation budgets, not new exact capacity tests.
The independent lower-owner limit fixtures remain distinct from this routing
evidence; no resource expectation was derived from successful telemetry.

## Fixed-source verification

Commands ran with the repository-pinned Node/MoonBit environment in PATH and
the existing toolchain home, without creating another dependency installation.
All successful checks below use the clean implementation SHA above.

```sh
node scripts/local-checks.mjs test moon --timeout-seconds 180 -- \
  --target js --jobs 1 \
  src/query_integration/captured_publication_preparation_wbtest.mbt \
  src/query_integration/client_result_transformation_wbtest.mbt \
  src/query_integration/resident_source_publication_wbtest.mbt \
  src/query_integration/physical_retention_wbtest.mbt

node scripts/local-checks.mjs build moon --timeout-seconds 180 -- \
  --target js --release src/connectors_builtin_node \
  src/connectors/duckdb/conformance

node scripts/local-checks.mjs test node --timeout-seconds 180 -- \
  --test-concurrency=1 \
  --test-name-pattern 'retained Named Result schema|retained Named Result ordering' \
  adapters/connectors/duckdb/node/test/retained-values-chain.test.mjs

node scripts/local-checks.mjs test node --timeout-seconds 90 -- \
  adapters/host-node/result-transformation-control.test.mjs \
  adapters/host-common/durable-result-payload.test.mjs
```

- Common JS **24/24**: `run-lhNZ7B` / `focused-test-5K9CkB`.
- Both consumed runtime roots built: `run-K5Vsvi`, 14 incremental tasks.
  The authorization fixture's existing release-root check also ran at this
  same source during Host startup. Generated bundles remain ignored.
- Actual Host **6/6**: `run-Ws6Ed2` / `focused-test-HiX4vF`. This includes the
  new unselected success/cancellation pair, the selected schema pair and the
  parent's Text-ordering pair; not all Host tests were executed.
- Adapter/durable controls **15/15**: `run-OKh3Wi` /
  `focused-test-0mXQC9`. Mock/control evidence is not public Host acceptance.
- Generated interfaces were issued with `moon info` for the six affected
  Host/bridge packages on JS. Two existing RelA unused-import warnings remain;
  compilation succeeded. Changed MoonBit files were individually formatted.
- Node/RelA and Workers assembly checks, Workers/Node Host fixture freshness,
  Node syntax, `git diff --check` and commit-message line limits passed.

Workers regeneration also restored template exports already present in the
parent/main source but missing from the old generated projections. It adds no
new Effect implementation or acceptance claim. The generators' read-only
checks confirm current template/output equality; independent row or identity
expectations were not regenerated from product output.

Diagnostic attempts are preserved under `_build/local-checks/attempts` and
`_build/focused-evidence`. `run-YSI52d` failed before Host cases ran because the
command omitted MoonBit from PATH; the two other files also had zero selected
cases under that Host-only filter. It is not product-failure or passing-test
evidence. Corrected commands selected the actual Host file and the controls
separately. Earlier precommit successes are not relabeled as clean-SHA checks.

## Remaining boundaries

This closes the JS captured Named Result preparation connection without an
extra Client selection. It does not close all Local retained paths. Explicit
blocking Native/direct-output convenience callers, replay metadata setup,
snapshot getters and field-list copies/validation still require separate
bounded connection or measurement. Physical chunk admission, trusted callbacks
and runtime allocation/contiguous-string latency remain distinct boundaries.
The parent's narrower inter-task Result projection limitation is unchanged.

No full Core, Wasm/Native execution, pristine packed/HTTPS, proof or performance
campaign ran. This unit's checkout runtime is not a pristine packaged artifact.
CI is recorded only for the exact submitted HEAD; Draft preparation is not
merge verification. No manual CI rerun or main merge was requested.
