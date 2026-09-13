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
