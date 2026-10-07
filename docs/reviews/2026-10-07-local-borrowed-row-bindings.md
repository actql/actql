# Borrowed row metadata execution

## Scope and integration

This unit follows #723, #717 and #708. #704 is already adopted by main.
Main `2d4dc269cdc8d35fe6af2bb1facc91e9f019685f` was normally merged at
`12ef6364938619425575c397490bd4600dcf3041` without conflicts. The current
Graph contracts remain authoritative; no old alias or identity fallback is
introduced. The final destination is main after the unmerged parents.

Source inspection found complete binding, unique-key and projection array
copies in `kernel_body()` during selected row start and capability checks.
This is a synchronous metadata-copy boundary, not a measured public stop
delay or a newly demonstrated wrong result. Initial lowering/preparation
still admits its metadata separately and is not certified by this unit.

## Existing owner connection

`lowering_relation/row_metadata_view.mbt` supplies opaque PreparedBindings
and PreparedUniqueKeys views. Indexed readers preserve canonical map order,
authored ordered occurrences, prior-slot references and the unique tuple.
The arrays remain private; the existing defensive body export is unchanged.
The projection view is bound to the exact lowered kernel, including checked
rename/drop, rather than requiring the author operation to be Select.

The existing BoundedBindingRows owner holds these views after its exact
input checks and metadata admission. Its bounded metadata phases use indexed
readers. The existing OrderedBindingsExecution owner selects an array or
prepared source and otherwise retains its original expression transitions,
charges, root registration and cleanup. Production row execution uses the
prepared source; existing internal array callers use the same driver.
There is no new evaluator, scheduler, ledger or compatibility fallback.

The bounded small-metadata lane scans at most eight binding names of at
most 64 UTF-16 units. Wide/long names keep the existing cursor phases.
Original entry admission, cumulative work, workspace limits and the
two-slots-per-binding reservation remain unchanged. Borrowing is not used
to silently lower a logical budget or claim a physical byte certificate.

## Evidence

Lowering tests verify opaque map/ordered/key readers, invalid indices and
independence from cleared defensive exports. The execution regression uses
64 independently specified literal bindings with a Unicode input name.
Quanta 1/7/256 produce the same values. Ordered shadowing independently
expects z=2, id=3 and a=4. Cancellation after a completed slot and during
the next expression preserves charged work and input custody, publishes no
output and releases roots/workspace once. Repeated cleanup reports no new
cleanup and does not double-release.

The broad affected-caller batch initially passed 95/99. Its four failures
were real rename/drop selection regressions: prepare_projection inspected
the author operation, although both are already lowered to Select. The
kernel-bound view fixes this without weakening assertions. Added long
rename/drop consumers and the unchanged exact/one-short caller tests then
passed 100/100 (`run-NaTBeW`, `focused-test-9NHvXJ`). Earlier new-fixture
failures used a missing ordered context and assumed repeated cleanup must
return true; both fixtures now follow the existing owner contract.

The public fixture sends a normal long-name, nine-binding map derive and
Select chain through Embedded Local and real retained Store. Its fixed
expected rows are (1,7) and (2,NULL). The shared harness reads all three
explicit Named Results, checks schema, independent consumers, request reuse,
delivered post-progress cancellation and final reclamation. Its public stop
barrier is not claimed inside a later binding; the private owner regression
establishes that specific boundary. The Host case and missing-evidence
regression passed 2/2 (`run-kzo5YP`, `focused-test-DYqjR3`). This is a
working-tree result with regenerated, untracked JS runtimes, not packed
or hosted CI evidence.

The ordered variant remains a separate public connection gap. Calling
`borrowedBindingsProgram(id, true)` in the same fixture constructs ten
authored occurrences: shadow the long input member, relay that slot, derive
value from relay, then seven independent literal outputs. It passes common
checking but fails normal submit before execution with
`RunHostTaskCompilationRejected`, whose typed cause is
`TaskGraph(Fragment(Pipeline(Encoding)))`. The public Client projects this
to `SubmissionUnknown` with a `ClientHostFailure` cause. Diagnostic evidence
is `run-4xWwtS` / `focused-test-FX05QG`; temporary diagnostic printing was
removed. `lowering_relation/kernel_encode.mbt` explicitly refuses
OrderedBindings because standalone emission lacks complete occurrence and
evidence bindings. This unit does not remove that guard, invent a Plan, or
claim public ordered-binding support. A later unit must connect the existing
fragment occurrence evidence into normal Plan compilation. Private ordered
execution and the public map path remain separately identified evidence.

The resource gate requires value, shadow, later-binding stop and public
roles. Removing a required role rejects the derive completion record.

## Remaining correspondence and validation

Native allocation correspondence is not certified here. The row state's
bindings/unique_keys become optional opaque views; its redundant ordered
field is removed. OrderedBindingsExecution now stores BindingExpressions.
The proof-only observer still expects Array length readers for bindings,
unique_keys and the parent's JSON path. G must align those exact readers,
the structural census and source recipes without broadening the restricted
short-name numeric/NULL DISTINCT pilot. The replacements are
`bindings.map(@lower.bindings_count).unwrap_or(0)`,
`unique_keys.map(@lower.unique_key_count).unwrap_or(0)` and
`json_path.map(@lower.json_pick_path_count).unwrap_or(0)`. BindingExpressions
also adds a prepared source to the existing expression owner. No pin is
blindly refreshed here; this is a concrete G handoff, not completed Native
correspondence.

Full Core, Wasm/Native execution, packed Local/HTTPS, Native capacity
campaigns, performance and public stop-latency measurement are not run.
Node Host and Workers generated-fixture freshness checks pass. Changed
MoonBit files match moonfmt and `git diff --check` passes. An accidentally
broader `moon fmt --check` reported existing differences in
`platform_native/executor_slot/executor_slot_native.mbt` and
`query_syntax/query_test.mbt`; neither source is changed by this unit.
This dependent PR remains Draft; these finite metadata fixes do not declare
Local Compute complete. The PR separates clean-SHA checks from working-tree
checks and hosted CI from local evidence.
