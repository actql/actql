# Local Compute attempts

The source-checkout `execution_relation` package provides a synchronous
one-shot wrapper for an existing checked `GeneratedSequence`:

1. Obtain upstream `CompletedOutput` values from successful sequence execution.
2. Use the existing `bind_completed_input(receiver, input_index,
   expected_producer, output)` function for each producer input.
3. Call `prepare_local_compute_attempt(generated, produced, max_entries)`.
4. Optionally cancel before starting with `cancel_local_compute_attempt`.
5. Call `execute_local_compute_attempt(attempt, limits)` once. Use the returned
   `CompletedSequence` and the existing `completed_output` accessors on success.

`local_compute_result` returns `NotComplete` before success, the execution
diagnostic on failure, or `Cancelled` after a successful pre-start cancellation.
It never yields a partially completed result. Start a new attempt to reuse a
successful producer with a different execution budget; failed attempts cannot
be restarted in place.

Preparation needs one entry per declared input and two per supplied binding
(membership bookkeeping and the owned container). Thus one declared producer
input and one binding need three entries. Input resource and logical budgets
are still checked by the receiving sequence during execution, not discounted
because the data is shared.

This is an internal integration building block, not a public Connector SPI or
CLI execution mode. Raw input, fresh source reads, asynchronous/in-flight
cancellation, durable capture and formal Program/Plan admission are not supplied
by this adapter. See [design](design/local-compute-attempt.md).

## Compute inside a physical task graph

The Local connector (`connectors/local`) provides
`prepare_local_compute_execution(choice, prepared, limits, measurement, ...)` for
an exactly selected Local candidate. It returns an opaque SDK
`SynchronousCompute`; it neither runs the calculation nor reserves resources.
Pass the handle to `physical_strategy.execute_captured_synchronous_task(run,
task, compute)`. The common driver checks selection and input ownership, reserves
the declared capacity, and installs a verified result with its holding atomically.
For a join task, bind the checked ceiling returned by
`captured_task_join_output_limit` to step zero when preparing the execution.

The execution handle is one-shot. Revoked inputs are rejected before the
implementation is called, and failure cannot publish a partial task result.
The common DAG no longer has a Local-specific execution entry point. Its SDK
contract is for trusted synchronous **no-I/O** implementations; it is not a way
to register arbitrary execution callbacks through ordinary Host request options.
This task-level entry does not authorize formal Program publication.

## Acquisition-internal residual building block

The acquisition adapter belongs to `execution_query`, not the fixed-input
`execution_relation` engine. Import that package for query preparation and receipt
APIs; there are no compatibility exports at the former engine locations.

For a broad, already received scan, `execution_query.prepare_query_sequence(query, generated,
max_work)` associates main's `sourceview_resolution.QueryAcquisition` with the
exact lowered pipeline and Parameter bindings. The supported sequence has one
input, a filter and a select; retain only the select node ID. A larger checked
pipeline is rejected rather than running its consumers before capture.

`evaluate_query_receipt(prepared, rows, max_received_rows, admission, execution)`
validates the entire receipt and runs that existing sequence. It returns either
a typed `ReceiptAdmission`/`Execution` failure or the usual `CompletedSequence`.
`query_sequence_requirement` returns the unchanged shared derivation. Fresh
execution budgets can reuse the immutable preparation.

This is **not acquisition completion**: callers still need verified source
coverage, authority, snapshot/access evidence, canonical logical guards and
observation capture before exposing an acquired input. The adapter supplies none
of those claims and cannot verify a native provider by seeing only its filtered
rows. See [residual boundary](design/query-residual-execution.md).
